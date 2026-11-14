#!/bin/bash
# Fetch and merge abue-ammar/tinycast:main, regenerate Tinycast.xcodeproj, and run verification.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

UPSTREAM_URL="https://github.com/abue-ammar/tinycast.git"
continue_merge=0
verify=1

for arg in "$@"; do
    case "$arg" in
        --continue) continue_merge=1 ;;
        --no-verify) verify=0 ;;
        -h|--help)
            echo "Usage: ./Scripts/sync-upstream.sh [--continue] [--no-verify]"
            exit 0
            ;;
        *)
            echo "✗ Unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

command -v xcodegen >/dev/null || {
    echo "✗ xcodegen not found. Install it with:  brew install xcodegen" >&2
    exit 2
}

if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "$UPSTREAM_URL"
fi
git remote set-url --push upstream DISABLE

git_dir="$(git rev-parse --git-dir)"

finish_merge_and_verify() {
    node Scripts/rebrand-strings.js
    xcodegen generate
    git add Tinycast.xcodeproj/project.pbxproj Tinycast/Resources/Localizable.xcstrings Tinycast/Resources/InfoPlist.xcstrings
    if [ -f "$git_dir/MERGE_HEAD" ]; then
        git commit --no-edit
    fi
    if [ "$verify" -eq 1 ]; then
        ./Scripts/lint.sh
        ./Scripts/run-tests.sh
    fi
    echo "✓ Synced with upstream/main"
}

if [ "$continue_merge" -eq 1 ]; then
    if [ ! -f "$git_dir/MERGE_HEAD" ]; then
        echo "✗ No merge in progress to continue." >&2
        exit 1
    fi
    unmerged="$(git diff --name-only --diff-filter=U)"
    if [ -n "$unmerged" ]; then
        echo "✗ Unresolved conflicts remain:" >&2
        echo "$unmerged" | sed 's/^/  - /' >&2
        exit 1
    fi
    finish_merge_and_verify
    exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "✗ Working tree has uncommitted changes. Commit or stash them first (e.g. git stash push -u)." >&2
    exit 1
fi

git fetch --tags upstream main

if git merge-base --is-ancestor upstream/main HEAD; then
    echo "✓ Already up to date with upstream/main ($(git rev-parse --short HEAD))"
    exit 0
fi

incoming="$(git rev-list --count HEAD..upstream/main)"
echo "Integrating $incoming commit(s) from upstream/main…"

if ! git merge --no-commit --no-ff upstream/main; then
    node Scripts/rebrand-strings.js --resolve-conflicts
    unmerged="$(git diff --name-only --diff-filter=U)"
    # Regenerating from project.yml resolves pbxproj file-list collisions deterministically.
    if echo "$unmerged" | grep -qx "Tinycast.xcodeproj/project.pbxproj" &&
       ! echo "$unmerged" | grep -qx "project.yml"; then
        git checkout --ours Tinycast.xcodeproj/project.pbxproj
    fi
    unmerged="$(git diff --name-only --diff-filter=U)"
    if [ -n "$unmerged" ]; then
        echo
        echo "✗ Manual conflict resolution needed in:" >&2
        echo "$unmerged" | sed 's/^/  - /' >&2
        echo >&2
        echo "Resolve the files above, git add them, then run:" >&2
        echo "  ./Scripts/sync-upstream.sh --continue" >&2
        exit 1
    fi
fi

finish_merge_and_verify
