#!/bin/bash
# Check or upload CI release signing, notarization, and Homebrew tap secrets for mj0lken/TermCast.
# Usage: ./Scripts/setup-release-secrets.sh [--status]
set -euo pipefail

REPO="mj0lken/TermCast"
ENV_NAME="release"

REQUIRED=(
    UPDATE_SIGNING_KEY
    DEVELOPER_ID_P12_BASE64
    DEVELOPER_ID_P12_PASSWORD
    NOTARY_KEY_P8_BASE64
    NOTARY_KEY_ID
    NOTARY_ISSUER_ID
)

ENV_SECRETS="$(gh secret list --env "$ENV_NAME" --repo "$REPO" --json name --jq '.[].name')"
REPO_SECRETS="$(gh secret list --repo "$REPO" --json name --jq '.[].name')"
REPO_VARS="$(gh variable list --repo "$REPO" --json name,value --jq '.[] | "\(.name)=\(.value)"')"

has_line() {
    printf '%s\n' "$1" | grep -Fqx "$2"
}

print_status() {
    echo "Release secrets on ${REPO} (environment '${ENV_NAME}'):"
    for key in "${REQUIRED[@]}"; do
        if has_line "$ENV_SECRETS" "$key"; then
            printf '  ✓ %s\n' "$key"
        else
            printf '  ○ %s (not set)\n' "$key"
        fi
    done
    echo
    echo "Optional repository secrets & variables:"
    if has_line "$ENV_SECRETS" "HOMEBREW_TAP_TOKEN" || has_line "$REPO_SECRETS" "HOMEBREW_TAP_TOKEN"; then
        echo "  ✓ HOMEBREW_TAP_TOKEN"
    else
        echo "  ○ HOMEBREW_TAP_TOKEN (not set — only needed for CI tap updates)"
    fi
    if [ -n "$REPO_VARS" ]; then
        printf '%s\n' "$REPO_VARS" | sed 's/^/  ✓ /'
    fi
}

if [ "${1:-}" = "--status" ]; then
    print_status
    exit 0
fi

print_status
echo

if ! has_line "$ENV_SECRETS" "DEVELOPER_ID_P12_BASE64"; then
    read -r -p "Path to exported Developer ID .p12 file (Enter to skip): " P12_PATH
    if [ -n "$P12_PATH" ]; then
        P12_PATH="${P12_PATH/#\~/$HOME}"
        base64 -i "$P12_PATH" | gh secret set DEVELOPER_ID_P12_BASE64 --env "$ENV_NAME" --repo "$REPO"
        read -r -s -p "Export password for $P12_PATH: " P12_PASS
        echo
        printf '%s' "$P12_PASS" | gh secret set DEVELOPER_ID_P12_PASSWORD --env "$ENV_NAME" --repo "$REPO"
        unset P12_PASS
    fi
fi

if ! has_line "$ENV_SECRETS" "NOTARY_KEY_P8_BASE64"; then
    read -r -p "Path to App Store Connect AuthKey_<ID>.p8 file (Enter to skip): " P8_PATH
    if [ -n "$P8_PATH" ]; then
        P8_PATH="${P8_PATH/#\~/$HOME}"
        base64 -i "$P8_PATH" | gh secret set NOTARY_KEY_P8_BASE64 --env "$ENV_NAME" --repo "$REPO"
        DEFAULT_KEY_ID="$(basename "$P8_PATH" .p8 | sed 's/^AuthKey_//')"
        read -r -p "App Store Connect Key ID [${DEFAULT_KEY_ID}]: " KEY_ID
        KEY_ID="${KEY_ID:-$DEFAULT_KEY_ID}"
        printf '%s' "$KEY_ID" | gh secret set NOTARY_KEY_ID --env "$ENV_NAME" --repo "$REPO"
        read -r -p "App Store Connect Issuer ID (UUID): " ISSUER_ID
        printf '%s' "$ISSUER_ID" | gh secret set NOTARY_ISSUER_ID --env "$ENV_NAME" --repo "$REPO"
    fi
fi

if ! has_line "$ENV_SECRETS" "HOMEBREW_TAP_TOKEN" && ! has_line "$REPO_SECRETS" "HOMEBREW_TAP_TOKEN"; then
    read -r -s -p "Fine-grained PAT for mj0lken/homebrew-tap Contents:write (Enter to skip): " TAP_PAT
    echo
    if [ -n "$TAP_PAT" ]; then
        printf '%s' "$TAP_PAT" | gh secret set HOMEBREW_TAP_TOKEN --env "$ENV_NAME" --repo "$REPO"
        unset TAP_PAT
    fi
fi

echo
ENV_SECRETS="$(gh secret list --env "$ENV_NAME" --repo "$REPO" --json name --jq '.[].name')"
REPO_SECRETS="$(gh secret list --repo "$REPO" --json name --jq '.[].name')"
print_status
