#!/bin/bash
# Creates a self-signed code-signing identity ("Better Widgets Local Signing") in the login keychain.
# Signing every build with the same identity lets macOS keep permissions (Accessibility,
# Location) across rebuilds; ad-hoc signatures look like a new app each time.
# Remove later with Keychain Access, or:
#   security delete-identity -c "Better Widgets Local Signing"
set -euo pipefail

NAME="Better Widgets Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "Identity \"$NAME\" already exists."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout pass:betterwidgets \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 $(openssl version | grep -q "^OpenSSL 3" && echo -legacy) 2>/dev/null

# -T lets codesign use the key without a keychain prompt on every build.
security import "$TMP/identity.p12" -k ~/Library/Keychains/login.keychain-db \
    -P betterwidgets -T /usr/bin/codesign >/dev/null

echo "Created code-signing identity \"$NAME\"."
