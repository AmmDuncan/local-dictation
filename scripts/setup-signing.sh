#!/usr/bin/env bash
# One-time: create a stable self-signed code-signing identity so the app keeps a
# constant signature across rebuilds. That stability is what lets macOS retain
# Microphone/Accessibility permissions instead of re-prompting every build.
#
# A GUI dialog asking for your login password may appear when trust is set —
# that's expected; approve it.
set -euo pipefail

IDENTITY="Local Dictation Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "Signing identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/req.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $IDENTITY
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# Use macOS's system LibreSSL — Homebrew OpenSSL 3 emits a PKCS#12 whose MAC the
# `security` tool can't verify. A transport password avoids empty-pass quirks.
OPENSSL=/usr/bin/openssl
P12_PASS="localdictation"

"$OPENSSL" req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/req.conf" >/dev/null 2>&1
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -name "$IDENTITY" -passout "pass:$P12_PASS" >/dev/null 2>&1

# Import key + cert; pre-authorize codesign to use the key without prompting.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null

# Trust the cert for code signing so it counts as a valid signing identity.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "Created and trusted signing identity '$IDENTITY'."
else
    echo "ERROR: identity not found after setup — codesign won't pick it up." >&2
    exit 1
fi
