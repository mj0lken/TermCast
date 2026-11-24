#!/bin/bash
# Launch <app>, cycle the palette, then fail on a leak, growth per cycle or a footprint over the ceiling.
# Usage: check-leaks.sh [app] [extra deep-link path ...]   e.g. check-leaks.sh "" settings/notch
set -euo pipefail

APP="${1:-build/DerivedData/Build/Products/Debug/Termcast Dev.app}"
[ $# -gt 0 ] && shift
EXTRA_LINKS=("$@")
CEILING_MB=100
CYCLES="${LEAKS_CYCLES:-5}"
GROWTH_LIMIT_MB=5
SETTLE_SECONDS=8
# Apple's App Intents leaves three XPC connection cycles at launch; no frame of ours is in them.
KNOWN_SYSTEM_LEAKS='com\.apple\.linkd\.autoShortcut'
REPORT="${LEAKS_REPORT:-build/leaks-report.txt}"

[ -d "$APP" ] || { echo "✗ no app at $APP — build it first" >&2 && exit 1; }
APP="$(cd "$APP" && pwd)"
PLIST="$APP/Contents/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
EXECUTABLE="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
SCHEME="$(/usr/libexec/PlistBuddy -c 'Print :TinycastURLScheme' "$PLIST")"

WORK="$(mktemp -d)"
cat >"$WORK/palette.swift" <<'SWIFT'
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
// 9 is the palette's own window level, below the notch's and above every normal window.
let isOpen = windows.contains {
    $0[kCGWindowOwnerPID as String] as? Int32 == pid && $0[kCGWindowLayer as String] as? Int == 9
}
print(isOpen ? "open" : "closed")
SWIFT

running_pid() { pgrep -f "^$EXECUTABLE" | head -n1 || true; }

# In megabytes; `footprint` is what Activity Monitor's Memory column shows.
footprint_mb() {
    vmmap --summary "$1" 2>/dev/null | awk -v field="$2" '
        /^Physical footprint/ {
            value = (field == "peak") ? $5 : $3
            if (field == "peak" && $0 !~ /peak/) next
            unit = substr(value, length(value)); number = substr(value, 1, length(value) - 1)
            if (unit == "G") number *= 1024
            if (unit == "K") number /= 1024
            printf "%.1f", number
            exit
        }'
}

palette_is_open() { [ "$(swift "$WORK/palette.swift" "$PID")" = "open" ]; }

# A command link shows its screen, and hides it when it is already showing: no Accessibility needed.
close_palette() {
    for _ in 1 2 3 4; do
        palette_is_open || return 0
        open -g -a "$APP" "$SCHEME://command/search-emoji"
        # Polled, so a link a busy machine handles late is not answered with a second toggle.
        for _ in 1 2 3 4 5; do
            sleep 2
            palette_is_open || return 0
        done
    done
    echo "✗ the palette would not close — is the screen locked?" >&2
    exit 1
}

if [ -n "$(running_pid)" ]; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    sleep 2
fi

# Stack logging names a leak's allocation site but inflates the footprint, so it is opt-in.
if [ -n "${LEAKS_STACKS:-}" ]; then
    open -g -n --env MallocStackLogging=lite "$APP"
else
    open -g -n "$APP"
fi
sleep "$SETTLE_SECONDS"
PID="$(running_pid)"
[ -n "$PID" ] || { echo "✗ $APP did not start" >&2 && exit 1; }
trap 'kill "$PID" 2>/dev/null || true; rm -rf "$WORK"' EXIT

# A launch by hand opens the launcher, so the idle reading waits for it to close.
close_palette
sleep "$SETTLE_SECONDS"
IDLE="$(footprint_mb "$PID" now)"

open -g -a "$APP" "$SCHEME://"
sleep 2
# Without this a locked screen measures nothing and every reading passes.
palette_is_open || { echo "✗ the palette did not open — is the screen locked?" >&2 && exit 1; }
PALETTE_OPEN="$(footprint_mb "$PID" now)"

WARM=""
for cycle in $(seq "$CYCLES"); do
    for link in "" "command/clipboard-history" "command/search-emoji" ${EXTRA_LINKS[@]+"${EXTRA_LINKS[@]}"}; do
        open -g -a "$APP" "$SCHEME://$link"
        sleep 1
    done
    close_palette
    # The first cycle fills the caches; growth is whatever the later ones add on top of it.
    if [ "$cycle" -eq 1 ]; then
        sleep "$SETTLE_SECONDS"
        WARM="$(footprint_mb "$PID" now)"
    fi
done
open -g -a "$APP" "$SCHEME://command/clipboard-history"
sleep 2
IN_USE="$(footprint_mb "$PID" now)"

close_palette
sleep "$SETTLE_SECONDS"
SETTLED="$(footprint_mb "$PID" now)"
PEAK="$(vmmap --summary "$PID" 2>/dev/null | sed -n 's/^Physical footprint (peak): *//p' | head -n1)"

mkdir -p "$(dirname "$REPORT")"
set +e
leaks "$PID" >"$REPORT" 2>&1
LEAKS_STATUS=$?
set -e
LEAK_LINE="$(grep -E '^Process [0-9]+: [0-9]+ leaks? for' "$REPORT" || true)"
ROOTS="$(grep -E '^ {6}[0-9]+ \(.*\) ROOT (LEAK|CYCLE)' "$REPORT" || true)"
OURS="$(printf '%s\n' "$ROOTS" | grep -vE "$KNOWN_SYSTEM_LEAKS" | grep -c . || true)"
SYSTEM="$(printf '%s\n' "$ROOTS" | grep -cE "$KNOWN_SYSTEM_LEAKS" || true)"
GROWTH="$(awk -v a="$SETTLED" -v b="$WARM" 'BEGIN { printf "%.1f", a - b }')"

cat <<EOF
| Step                    | Memory |
| ----------------------- | ------ |
| Idle after launch       | ${IDLE} MB |
| Palette open            | ${PALETTE_OPEN} MB |
| Feature in use (peak)   | ${IN_USE} MB (process peak ${PEAK:-unknown}) |
| Palette closed, settled | ${SETTLED} MB |

Growth over $((CYCLES - 1)) further cycles after the first: ${GROWTH} MB
Leak roots: ${OURS} to fix, ${SYSTEM} known in Apple's App Intents
${LEAK_LINE:-leaks could not inspect the process}
Full report: $REPORT (rerun with LEAKS_STACKS=1 for allocation stacks)
EOF

FAILED=0
if [ -z "$LEAK_LINE" ] || [ "$LEAKS_STATUS" -gt 1 ]; then
    echo "✗ leaks could not inspect the process (exit $LEAKS_STATUS)" >&2
    FAILED=1
fi
if [ "$OURS" -gt 0 ]; then
    echo "✗ $OURS leak root(s) outside the known system ones" >&2
    FAILED=1
fi
if awk -v g="$GROWTH" -v limit="$GROWTH_LIMIT_MB" 'BEGIN { exit !(g > limit) }'; then
    echo "✗ footprint grew $GROWTH MB across cycles, over the $GROWTH_LIMIT_MB MB limit" >&2
    FAILED=1
fi
for value in "$IDLE" "$PALETTE_OPEN" "$IN_USE" "$SETTLED"; do
    if awk -v v="$value" -v c="$CEILING_MB" 'BEGIN { exit !(v > c) }'; then
        echo "✗ footprint $value MB is over the $CEILING_MB MB ceiling" >&2
        FAILED=1
    fi
done
[ "$FAILED" -eq 0 ] && echo "✓ no leaks of ours, no growth, footprint under $CEILING_MB MB"
exit "$FAILED"
