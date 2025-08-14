#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

cargo build -p trusted-setup --release
cargo build -p preprocess --release
cargo build -p prove --release
cargo build -p verify --release

TARGET="dist-mac"
BACKEND_PATH="backend-lib/icicle"

COMMON_TARBALL="icicle_3_8_0-macOS.tar.gz"
BACKEND_TARBALL="icicle_3_8_0-macOS-Metal.tar.gz"
COMMON_URL="https://github.com/ingonyama-zk/icicle/releases/download/v3.8.0/$COMMON_TARBALL"
BACKEND_URL="https://github.com/ingonyama-zk/icicle/releases/download/v3.8.0/$BACKEND_TARBALL"

APP_SIGN_ID='3524416ED3903027378EA41BB258070785F977F9'
NOTARY_PROFILE='tokamak-zk-evm-backend'
OUT_ZIP='tokamak-zk-evm-mac.zip'

command -v curl >/dev/null 2>&1 || { echo "curl is required but not found"; exit 1; }
command -v tar  >/dev/null 2>&1 || { echo "tar is required but not found"; exit 1; }

echo "[*] Downloading backend package..."
curl -fL --retry 3 -o "$BACKEND_TARBALL" "$BACKEND_URL"
echo "[*] Downloading common runtime package..."
curl -fL --retry 3 -o "$COMMON_TARBALL" "$COMMON_URL"

echo "[*] Extracting packages..."
tar -xzf "$BACKEND_TARBALL"
tar -xzf "$COMMON_TARBALL"

echo "[*] Installing to ${TARGET}/${BACKEND_PATH} ..."
mkdir -p "${TARGET}/${BACKEND_PATH}"
cp -r icicle/* "${TARGET}/${BACKEND_PATH}"

echo "[*] Cleaning up temporary files..."
rm -rf "$BACKEND_TARBALL" "$COMMON_TARBALL" icicle

echo "[*] Copying executable binaries..."
mkdir -p "${TARGET}/bin"
cp -vf target/release/trusted-setup "${TARGET}/bin"
cp -vf target/release/preprocess "${TARGET}/bin"
cp -vf target/release/prove "${TARGET}/bin"
cp -vf target/release/verify "${TARGET}/bin"
echo "✅ copied to ${TARGET}/bin"

echo "[*] Configuring @rpath of the binaries..."
RPATH="@executable_path/../${BACKEND_PATH}/lib"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

install_name_tool -add_rpath "$RPATH" "${TARGET}/bin/trusted-setup"
install_name_tool -add_rpath "$RPATH" "${TARGET}/bin/prove"
install_name_tool -add_rpath "$RPATH" "${TARGET}/bin/preprocess"
install_name_tool -add_rpath "$RPATH" "${TARGET}/bin/verify"
echo "✅ @rpath set to ${RPATH}"

echo "[*] Signing on all distribution..."
find "$TARGET" -type f \( -perm -111 -o -name "*.dylib" -o -name "*.so" \) -print0 | xargs -0 -I{} codesign --force --options runtime --timestamp -s "$APP_SIGN_ID" "{}"
# find "$TARGET" -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \) -print0 | xargs -0 -I{} codesign --verify --strict --verbose=2 "{}"
echo "✅ Signed"

echo "[*] Packaging and notarying..."
rm -f "$OUT_ZIP"
( cd "$TARGET" && ditto -c -k --sequesterRsrc . "../$OUT_ZIP" )
xcrun notarytool submit "$OUT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
# xcrun stapler staple "$OUT_ZIP"
echo "✅ Packaging for MacOS has been completed"