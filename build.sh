#!/bin/zsh
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$root/.." && pwd)/Pinchpad.app"
sdk="$(xcrun --show-sdk-path --sdk macosx)"
if ps -axo command= | awk -v executable="$app/Contents/MacOS/Pinchpad" '$1 == executable { found = 1 } END { exit !found }'; then
  echo "Quit the running Pinchpad before rebuilding its existing app bundle." >&2
  exit 1
fi
sign_dir="$HOME/Library/Application Support/Pinchpad/signing"
keychain="$sign_dir/pinchpad.keychain-db"
p12="$sign_dir/pinchpad.p12"
identity="Pinchpad Local"
password="pinchpad-local"
if [[ -d "$app" && ( ! -f "$p12" || ! -f "$keychain" ) ]]; then
  echo "Existing Pinchpad.app requires its original signing identity; refusing to replace it." >&2
  exit 1
fi
mkdir -p "$sign_dir"
if [[ ! -f "$p12" ]]; then
  tmp="$(mktemp -d)"
  openssl req -new -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -subj "/CN=$identity" -out "$tmp/csr.pem"
  cat > "$tmp/ext.cnf" << 'EOF'
basicConstraints=CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
  openssl x509 -req -in "$tmp/csr.pem" -signkey "$tmp/key.pem" -days 3650 -out "$tmp/cert.pem" -extfile "$tmp/ext.cnf"
  openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$p12" -passout pass:"$password" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1
  rm -f "$tmp/key.pem" "$tmp/csr.pem" "$tmp/ext.cnf" "$tmp/cert.pem"
  rmdir "$tmp"
fi
if ! security find-certificate -c "$identity" "$keychain" >/dev/null 2>&1; then
  if [[ -f "$keychain" ]]; then
    echo "Original signing certificate is missing from $keychain; refusing to replace the keychain." >&2
    exit 1
  fi
  security create-keychain -p "$password" "$keychain"
  security unlock-keychain -p "$password" "$keychain"
  security set-keychain-settings "$keychain"
  security import "$p12" -k "$keychain" -P "$password" -T /usr/bin/codesign -T /usr/bin/security -f pkcs12
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
fi
security unlock-keychain -p "$password" "$keychain"
signing_hash="$(security find-certificate -c "$identity" -Z "$keychain" | sed -n 's/^SHA-1 hash: //p' | head -1)"
if [[ -z "$signing_hash" ]]; then
  echo "Original signing certificate is unavailable; refusing to build." >&2
  exit 1
fi
if [[ -d "$app" ]]; then
  existing_hash="$(codesign -d -r- "$app" 2>&1 | sed -n 's/.*certificate leaf = H"\([A-Fa-f0-9]*\)".*/\1/p')"
  if [[ -z "$existing_hash" || "${existing_hash:u}" != "${signing_hash:u}" ]]; then
    echo "Signing certificate does not match the existing Pinchpad.app; refusing to replace it." >&2
    exit 1
  fi
fi
build_dir="$(mktemp -d)"
trap 'rm -f "$build_dir/Pinchpad"; rmdir "$build_dir"' EXIT
swiftc -swift-version 5 -parse-as-library -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$sdk" \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
  -lsqlite3 \
  -o "$build_dir/Pinchpad" \
  "$root"/Sources/*.swift
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Info.plist" "$app/Contents/Info.plist"
cp "$root/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$root"/Resources/MenuBarIcon*.png "$app/Contents/Resources/"
printf 'APPL????' > "$app/Contents/PkgInfo"
mv "$build_dir/Pinchpad" "$app/Contents/MacOS/Pinchpad"
codesign --force --sign "$signing_hash" --keychain "$keychain" --identifier app.local.pinchpad "$app"
codesign --verify --deep --strict "$app"
echo "built $app"
