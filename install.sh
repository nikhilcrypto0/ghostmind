#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP="/Applications/GhostMind.app"
IDENTITY="GhostMind Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo ""
echo "  GhostMind — Installer"
echo "  ────────────────────────────────────"
echo ""

# ──────────────────────────────────────────────────────────────────────
# Signing identity setup
#
# Ad-hoc signing (codesign --sign -) creates a different signature on every
# rebuild. macOS TCC ties Screen Recording / Mic / Accessibility grants to
# the signature, so every install resets those permissions.
#
# A persistent self-signed certificate gives every build the same identity,
# so TCC remembers your grants across rebuilds.
#
# First run: creates the cert (one dialog asks for keychain password to
# trust it for code signing). All subsequent runs are silent.
# ──────────────────────────────────────────────────────────────────────

ensure_signing_identity() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
        echo "  ✓ Using existing signing identity: $IDENTITY"
        return 0
    fi

    echo "  First-time setup: creating local signing certificate '$IDENTITY'"
    echo "  macOS will ask you to authorize trusting it for code signing."
    echo ""

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    cat > "$tmpdir/cert.conf" <<EOF
[ req ]
distinguished_name = req_dn
x509_extensions = v3_ext
prompt = no
[ req_dn ]
CN = $IDENTITY
[ v3_ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

    # 10-year self-signed code-signing cert
    if ! openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$tmpdir/key.pem" \
        -out "$tmpdir/cert.pem" \
        -days 3650 \
        -config "$tmpdir/cert.conf" >/dev/null 2>&1; then
        echo "  ⚠ Could not generate certificate — falling back to ad-hoc"
        return 1
    fi

    # Bundle with PBE-SHA1-3DES (macOS keychain compatible).
    # macOS's `security import` rejects newer PKCS#12 algorithms openssl 3
    # uses by default; explicitly specifying legacy PBE works on both
    # LibreSSL (macOS bundled) and openssl 3.
    if ! openssl pkcs12 -export \
        -inkey "$tmpdir/key.pem" \
        -in "$tmpdir/cert.pem" \
        -out "$tmpdir/cert.p12" \
        -password pass:ghostmind \
        -keypbe PBE-SHA1-3DES \
        -certpbe PBE-SHA1-3DES \
        -macalg SHA1 >/dev/null 2>&1; then
        echo "  ⚠ Could not package certificate — falling back to ad-hoc"
        return 1
    fi

    # Import into login keychain; -T allows codesign to use the key.
    if ! security import "$tmpdir/cert.p12" \
        -k "$KEYCHAIN" \
        -P "ghostmind" \
        -T /usr/bin/codesign >/dev/null 2>&1; then
        echo "  ⚠ Keychain import failed — falling back to ad-hoc"
        return 1
    fi

    # Trust the cert for code signing. This pops a one-time auth dialog.
    if ! security add-trusted-cert \
        -r trustRoot -p codeSign \
        -k "$KEYCHAIN" \
        "$tmpdir/cert.pem" 2>/dev/null; then
        echo "  ⚠ Trust step failed — falling back to ad-hoc"
        return 1
    fi

    # Allow codesign access without per-invocation password prompts.
    security set-key-partition-list \
        -S apple-tool:,apple:,codesign: \
        -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
        echo "  ✓ Created signing identity '$IDENTITY' (valid 10 years)"
        return 0
    else
        echo "  ⚠ Identity not visible after setup — falling back to ad-hoc"
        return 1
    fi
}

# Build
echo "  Building..."
swift build -c release 2>&1 | grep -E "Build complete|error:|warning:" || true
echo ""

# Pick signing method based on whether we have a persistent identity
SIGN_ARGS=()
if ensure_signing_identity; then
    SIGN_ARGS=(--force --options=runtime --sign "$IDENTITY")
else
    SIGN_ARGS=(--force --sign -)
fi
echo ""

# Kill any running instance
pkill -x GhostMind 2>/dev/null || true
sleep 0.3

# Build app bundle
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/GhostMind "$APP/Contents/MacOS/GhostMind"
cp Info.plist               "$APP/Contents/Info.plist"
cp AppIcon.icns             "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true

# Sign (with entitlements if present).
# audio-input must be in the entitlements file when hardened runtime is on,
# otherwise macOS silently denies AVCaptureDevice.requestAccess without
# showing a prompt — see the long debugging session that led to this guard.
if [ -f GhostMind.entitlements ]; then
    if ! grep -q "com.apple.security.device.audio-input" GhostMind.entitlements; then
        echo "  ⚠ GhostMind.entitlements is missing com.apple.security.device.audio-input"
        echo "    Microphone permission dialog will not appear under hardened runtime."
        echo "    Aborting — fix the entitlements file before reinstalling."
        exit 1
    fi
    codesign "${SIGN_ARGS[@]}" --entitlements GhostMind.entitlements "$APP" 2>/dev/null
else
    codesign "${SIGN_ARGS[@]}" "$APP" 2>/dev/null
fi

# Confirm what we signed with
SIG_AUTHORITY=$(codesign -dvvv "$APP" 2>&1 | grep "Authority=" | head -1 | sed 's/Authority=//')
if [ -n "$SIG_AUTHORITY" ] && [ "$SIG_AUTHORITY" != "(unsigned)" ]; then
    echo "  ✓ Signed with: $SIG_AUTHORITY"
    if [ "$SIG_AUTHORITY" = "$IDENTITY" ]; then
        echo "  ✓ TCC grants will persist across rebuilds"
    fi
else
    echo "  ✓ Signed (ad-hoc — permissions will reset on rebuild)"
fi
echo "  ✓ Installed to $APP"

echo ""
echo "  ────────────────────────────────────"
echo "  Done. Launching GhostMind..."
echo ""

open "$APP"
