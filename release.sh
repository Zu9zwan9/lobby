#!/bin/bash
# Local release helper. Signing identity and notary profile stay out of the repo.
set -e
cd "$(dirname "$0")"

SIGN_ID="${SIGN_ID:-Developer ID Application: BBMM TECHNOLOGIES INC. (KSDM65552F)}"
PROFILE="${KEYCHAIN_PROFILE:-lobby}"

pkill -f "Lobby.app/Contents/MacOS/Lobby" 2>/dev/null || true

make app
make sign SIGN_ID="$SIGN_ID"
make dmg  SIGN_ID="$SIGN_ID"

echo "--- SIGNATURE ---"
codesign -dv --verbose=4 build/Lobby.app 2>&1 | grep -E 'Authority|Identifier|TeamIdentifier|Timestamp|flags'

echo "--- GATEKEEPER (expects 'rejected' until notarized) ---"
spctl -a -vvv -t exec build/Lobby.app 2>&1 || true

if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    make notarize SIGN_ID="$SIGN_ID" KEYCHAIN_PROFILE="$PROFILE"
    spctl -a -vvv -t exec build/Lobby.app 2>&1 || true
else
    echo "--- NOTARIZATION SKIPPED ---"
    echo "No keychain profile '$PROFILE'. Create one once, then rerun this script:"
    echo "  xcrun notarytool store-credentials $PROFILE \\"
    echo "    --apple-id <your-apple-id> --team-id KSDM65552F --password <app-specific-password>"
fi

ls -la build/
