# Release

How a build reaches a user. The local development loop is in [development.md](development.md);
the signing identity itself is in [signing.md](signing.md).

## Packaging & publishing locally

```sh
./Scripts/build-dmg.sh                # -> build/Termcast-<version>.dmg (version from project.yml)
./Scripts/build-dmg.sh 0.1.1          # -> build/Termcast-0.1.1.dmg
./Scripts/publish-release.sh 0.1.1    # builds arm64 + Universal, publishes v0.1.1, bumps mj0lken/homebrew-tap
./Scripts/publish-release.sh 0.2.0 beta
```

`build-dmg.sh` builds a single local Release `Termcast.app` signed with `Tinycast Self-Signed` into
`build/`. `publish-release.sh` runs from a clean `main` synced with `origin/main` using Xcode 27+,
builds and slice-verifies both `arm64` and `Universal` variants, publishes the GitHub Release, and
updates `Casks/termcast.rb` in `mj0lken/homebrew-tap` (or notarizes automatically when Developer ID
and App Store Connect Notary variables are exported). CI releases run via `.github/workflows/release.yml`, below.

## Signing & Gatekeeper

CI releases are signed with the team's Developer ID, notarized and stapled, so a downloaded DMG
opens without a Gatekeeper warning. Local builds, `build-dmg.sh` included, keep signing with
`Tinycast Self-Signed` and are never notarized. Full details in [signing.md](signing.md).

## How the in-app updater consumes a release

Every release publishes three assets from one build: `Termcast-<version>.dmg`, which people download
by hand and which the cask installs, `Termcast-<version>.zip`, which the in-app updater installs, and
`Termcast-<version>.zip.sig`, the zip's signature by the release key. The zip is produced with
`ditto -c -k --keepParent --sequesterRsrc` — the only zip that leaves the code signature verifiable,
which matters because the updater refuses any bundle it cannot prove is ours.

A stable release publishes two more from the `universal` job, `Termcast-Universal-<version>.dmg` and
`.zip`, built from the same commit at the same version and bundle id but with both slices. They are
uploaded _after_ the thin pair, which keeps the thin zip first in the asset list so builds predating
architecture-aware selection keep choosing it.

Three things a release must keep true, or the updater skips it:

- **It carries a `.zip` asset this Mac can run.** A DMG-only release is not installable and is not
  offered, and an Intel build is offered nothing rather than a thin arm64 zip.
- **The tag parses as `vMAJOR.MINOR.PATCH` or `vMAJOR.MINOR.PATCH-beta.N`,** and agrees with the
  `prerelease` flag. A tag of any other shape is treated as mis-published and skipped.
- **It is not a draft.**

**Every cask declares `auto_updates true`.** That is Homebrew's flag for an app that manages its own
version, and it is what keeps `brew update && brew upgrade` from fighting an app that updated itself:
brew never reports Tinycast outdated, never re-downloads it, and never rolls a self-updated copy back.
Removing that line would reintroduce exactly those three problems. See
[features/updates.md](features/updates.md).

## Pull request review

`.github/workflows/pr-checks.yml` runs on every PR to `main`: model purity, `Scripts/lint.sh`, a Debug
build and `Scripts/run-tests.sh`, on an Xcode 27 runner. It cannot launch the app or measure memory, so
the rest of [testing.md](testing.md#definition-of-done) is still run locally before a PR is opened.

It runs on the runner the `PR_CHECKS_RUNNER` repository variable names, then `MACOS_RUNNER`, then
`macos-latest`. `PR_CHECKS_RUNNER` is kept apart from `MACOS_RUNNER` so a self-hosted Mac can take PR
checks without also taking releases, whose signing step changes that Mac's keychain search list.

## Releasing

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions, no local machine
needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `beta` or `stable`. Each builds a distinct app (`Termcast Beta.app` / `Termcast.app`)
  with its own bundle id, alongside the local `Termcast Dev.app`. Beta gets an auto-incrementing
  `-beta.N` suffix (`N` = the Actions run number) so re-running never collides; stable ships the
  version as-is.
- **version** — base semver, e.g. `0.2.0`.

Its first step is `Scripts/check-migrations.sh`: a migration that a stable release already shipped
stops the run until it is deleted ([migrations.md](migrations.md)). The check reads tags and history,
so the checkout fetches every commit without blobs.

It builds on an `xcode-27` runner with the newest released Xcode 27 and publishes a GitHub Release
tagged `v<full-version>` with a versioned DMG and zip asset, marked prerelease for beta. On success
it also announces the release on Discord. A stable run also dispatches the Website workflow, because
the site reads the latest version and the [changelog](https://tinycast.dev/changelog/) from GitHub at
build time.

A stable run then fans out to a second job, `universal`, which rebuilds the same commit with
`ARCHS="arm64 x86_64"` and attaches `Termcast-Universal-<version>.dmg` / `.zip` to the release the
first job created, then bumps `tinycast-universal`. macOS 26 is the last release that boots on Intel,
and those Macs need both slices. Both jobs pin `ARCHS` explicitly and assert the slices on _every_
shipping binary — the app, `ClipboardTextHelper`, `FileIndexHelper` and `Tinycast Dictation`:
trusting `ARCHS_STANDARD` is what shipped a thin arm64 build to Intel users once already, and it
also keeps the Apple silicon download from silently gaining a slice it never needs. A thin helper
inside a universal app is the quiet form of the same bug: the app boots on Intel and only clipboard
OCR or dictation stops working.

Both jobs run in the `release` environment, which holds the signing and notary secrets and deploys
from `main` only ([signing.md](signing.md#2-the-release-secrets)). After `verify-signature.sh`,
`Scripts/package-release.sh` packs and signs the DMG, submits it once with `notarytool --wait`, and
staples the ticket to the DMG and to the app before zipping it, so the updater's zip is stapled too.
Any status but `Accepted` prints Apple's log and stops the run before anything is published.
`Scripts/sign-update.swift` then signs the zip, and fails the run if the built app trusts a different
update key. `Scripts/check-update-path.sh` runs just before notarizing, and fails the run unless the
last release on the channel would install this build ([signing.md](signing.md#update-trust)).

Channel builds override `TINYCAST_BUNDLE_IDENTIFIER`, not the target-wide `PRODUCT_BUNDLE_IDENTIFIER`.
The Dictation helper derives its own identifier with a `.dictation` suffix; signature verification
checks that its bundle and signing identifiers agree and remain distinct from the main app.

### Release notes

`Scripts/release-notes.sh` composes the release body, and CI runs it just before `gh release create`.
It is safe to run by hand against any tag — it only reads:

```sh
CHANNEL=beta TAG=v0.9.13-beta.61 ./Scripts/release-notes.sh /tmp/body.md /tmp/discord.md
```

The changelog itself comes from GitHub's own release-notes API, which lists every merged PR with its
author and number — so contributors are credited without anyone maintaining a `CHANGELOG.md`, and
without Conventional Commits. **Nothing is ever committed to this repo**: the tag is created
server-side by `gh release create`, and no release, bot or version-bump commit exists.

Two details the script exists for:

- **The previous tag is picked per channel.** Beta and stable tags interleave on `main` — the same
  commit can carry both — so "the previous release" is only ever right within one channel. A stable
  release therefore spans every beta since the last stable.
- **The body is split by `<!-- tinycast:install -->`.** Everything above it is the changelog;
  everything below is the install text, which only a download page needs. The website's changelog
  cuts at that marker in `website/src/lib/changelog.ts`. Full PR URLs are shortened to `#304`, which
  still autolinks on the web.

The Discord announcement carries the same changelog, truncated to fit Discord's component limit, and
pings `@everyone`.

### The bundle id handoff

Tinycast moved from `com.tinycast.app` (and `.beta`, `.dev`) to `com.abueammar.tinycast`, because
another team holds the old App ID and iCloud needs one. A copy from before the move refuses any update
whose bundle id differs from its own, and that check is in code already shipped. So until
**2027-05-13** every release also publishes a handoff, built from the `TinycastHandoff` target:

- **It wears the old id and the release's version**, so the old copy's checks pass, and it carries the
  real app under `Contents/Helpers/`. `wrap-handoff.sh` embeds the stapled app, re-seals the handoff
  and asserts its id and version; `package-handoff.sh` then notarizes, staples, zips and signs it.
- **It is uploaded first, in its own call:** `Tinycast-<version>-Handoff.zip` in the build job,
  `Tinycast-Universal-<version>-Handoff.zip` before the universal zip. An old copy takes the first zip
  it can run; `ReleaseFeed` skips both for a copy that has moved.
- **On launch it hands over and gets out of the way:** it records whether the old id was a login
  item, unregisters it, swaps the app it carries into its own place, opens it and exits.
  `BundleIdentifierMigration` then moves the preferences, folders and login item to the new id, and
  repoints every saved path into the old folders. The user clicks Update and Relaunch once, then grants the macOS permissions again and
  re-enters any AI API key or MCP secret: the Keychain asks before another id reads an item, and the
  move must never ask.

The casks in homebrew/cask still name the old id in `uninstall quit:` and `zap`, and need the new one
after the first stable handoff release; the universal cask in the tap needs the same. On 2027-05-13
the migration check fails, and the handoff goes with everything its row in
[migrations.md](migrations.md) lists.

### Homebrew cask (`mj0lken/homebrew-tap`)

`Casks/termcast.rb` in [`mj0lken/homebrew-tap`](https://github.com/mj0lken/homebrew-tap) serves both
Apple Silicon (`Termcast-<version>.dmg`) and Intel (`Termcast-Universal-<version>.dmg`) via Homebrew's
`arch arm: "", intel: "-Universal"` stanza (`brew install --cask mj0lken/tap/termcast`).

`./Scripts/publish-release.sh` updates `version` and both `arm:` / `intel:` `sha256` lines directly
via `gh`. In CI (`.github/workflows/release.yml`), the `universal` job updates the same three lines
when `HOMEBREW_TAP_TOKEN` (a fine-grained PAT with **Contents: read/write** on `mj0lken/homebrew-tap`)
and `HOMEBREW_TAP_REPO=mj0lken/homebrew-tap` are set; without the token it logs a notice and skips so
the GitHub Release still publishes.
