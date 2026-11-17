// Runs under /usr/bin/osascript: macOS answers now-playing queries only for Apple-signed processes.
ObjC.import("Foundation");
ObjC.import("stdlib");
$.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework").load;

const PLAYBACK_STATE_PLAYING = 1;
const ARTWORK_SIDE = 300;
const INFO_KEY_PREFIX = "kMRMediaRemoteNowPlayingInfo";

const output = $.NSFileHandle.fileHandleWithStandardOutput;
const input = $.NSFileHandle.fileHandleWithStandardInput;
const mainQueue = $.NSOperationQueue.mainQueue.underlyingQueue;
let lineArtworkID;
let sentArtworkLength = 0;
let sentLine = "";

function infoValue(info, key) {
  const value = info.objectForKey(INFO_KEY_PREFIX + key);
  return value.isNil() ? undefined : value;
}

function infoField(info, key) {
  const value = infoValue(info, key);
  return value === undefined ? undefined : ObjC.unwrap(value);
}

function describeClient(response, message) {
  const path = response.playerPath;
  if (path.isNil() || path.client.isNil()) return;
  message.bundleID = ObjC.unwrap(path.client.bundleIdentifier);
  message.parentBundleID = ObjC.unwrap(path.client.parentApplicationBundleIdentifier);
  message.appName = ObjC.unwrap(path.client.displayName);
}

function describeItem(item, message) {
  const info = item.nowPlayingInfo;
  if (info.isNil()) return;
  const timestamp = infoValue(info, "Timestamp");
  message.artworkID = infoField(info, "ArtworkIdentifier") || ObjC.unwrap(item.identifier);
  message.title = infoField(info, "Title");
  message.artist = infoField(info, "Artist");
  message.album = infoField(info, "Album");
  message.duration = infoField(info, "Duration");
  message.elapsed = infoField(info, "ElapsedTime");
  message.rate = infoField(info, "PlaybackRate");
  message.timestamp = timestamp === undefined ? undefined : Number(timestamp.timeIntervalSince1970);
}

// Tinycast keeps an image only while consecutive lines share an artworkID; resend on any break.
function forgetArtworkUnlessContinuing(message) {
  const hasTrack = String(message.title || "").trim() !== "";
  if (!hasTrack || message.artworkID !== lineArtworkID) sentArtworkLength = 0;
  lineArtworkID = hasTrack ? message.artworkID : undefined;
}

// A state change repeats the whole response, so each image crosses the pipe only once.
function attachArtwork(item, message) {
  forgetArtworkUnlessContinuing(message);
  if (lineArtworkID === undefined || item.isNil()) return;
  const artwork = item.artwork;
  if (artwork.isNil() || artwork.imageData.isNil()) return;
  const length = Number(artwork.imageData.length);
  if (length === sentArtworkLength) return;
  sentArtworkLength = length;
  message.artwork = ObjC.unwrap(artwork.imageData.base64EncodedStringWithOptions(0));
}

function currentItem(response) {
  if (response.isNil() || response.playbackQueue.isNil()) return $();
  return response.playbackQueue.contentItemWithOffset(0);
}

function describe(response, item) {
  const message = {};
  if (response.isNil()) return message;
  message.isPlaying = Number(response.playbackState) === PLAYBACK_STATE_PLAYING;
  describeClient(response, message);
  if (!item.isNil()) describeItem(item, message);
  return message;
}

function emit(controller) {
  const response = controller.response;
  const item = currentItem(response);
  const message = describe(response, item);
  attachArtwork(item, message);
  const line = JSON.stringify(message) + "\n";
  if (line === sentLine) return;
  sentLine = line;
  output.writeData($(line).dataUsingEncoding($.NSUTF8StringEncoding));
}

const responseChanged = { types: ["void", ["id", "id"]], implementation: emit };

ObjC.registerSubclass({
  name: "TinycastNowPlayingRelay",
  methods: {
    "controller:didLoadResponse:": responseChanged,
    "controller:didUpdateResponse:": responseChanged,
    "controller:didLoadArtworkForContentItems:": responseChanged,
    // Tinycast never writes to stdin, so data here can only be the end-of-file its exit leaves.
    "inputClosed:": { types: ["void", ["id"]], implementation: function () { $.exit(0); } },
  },
});

const queueRequest = $.NSClassFromString("MRPlaybackQueueRequest").defaultPlaybackQueueRequest;
queueRequest.setArtworkWidth(ARTWORK_SIDE);
queueRequest.setArtworkHeight(ARTWORK_SIDE);

const destination = $.NSClassFromString("MRDestination").localDestination;
const configuration = $.NSClassFromString("MRNowPlayingControllerConfiguration").alloc.initWithDestination(destination);
configuration.setRequestPlaybackState(true);
configuration.setRequestPlaybackQueue(true);
configuration.setRequestClientProperties(true);
configuration.setPlaybackQueueRequest(queueRequest);

const relay = $.TinycastNowPlayingRelay.alloc.init;
const controller = $.NSClassFromString("MRNowPlayingController").alloc.initWithConfiguration(configuration);
// Callbacks must land on the main thread: JavaScript run from a worker queue waits for the run loop.
controller.setWorkerQueue(mainQueue);
controller.setDelegate(relay);
controller.beginLoadingUpdates;

$.NSNotificationCenter.defaultCenter.addObserverSelectorNameObject(
  relay, "inputClosed:", $.NSFileHandleDataAvailableNotification, input);
input.waitForDataInBackgroundAndNotify;

while (true) {
  $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.distantFuture);
}
