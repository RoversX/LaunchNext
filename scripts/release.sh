#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="LaunchNext.xcodeproj"
SCHEME="LaunchNext"
CONFIGURATION="Release"

cd "${ROOT_DIR}"

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  clean build

BUILT_PRODUCTS_DIR="$(xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  -showBuildSettings \
  | awk -F ' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { print $2 }' \
  | tail -n 1)"

APP_PATH="${BUILT_PRODUCTS_DIR}/LaunchNext.app"
BUILD_DIR="$(cd "${BUILT_PRODUCTS_DIR}/../.." && pwd)"
RELEASE_DIR="${BUILD_DIR}/dist"

rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: Release app not found at ${APP_PATH}" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
if [[ -z "${VERSION}" ]]; then
  echo "error: Could not read CFBundleShortVersionString from ${APP_PATH}" >&2
  exit 1
fi

ZIP_NAME="LaunchNext${VERSION}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
CHECKSUMS_PATH="${RELEASE_DIR}/checksums.txt"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

(
  cd "${RELEASE_DIR}"
  shasum -a 256 "${ZIP_NAME}" > "${CHECKSUMS_PATH}"
)

SHA256="$(awk '{print $1}' "${CHECKSUMS_PATH}")"

echo "Release artifacts:"
echo "  App: ${APP_PATH}"
echo "  ${ZIP_PATH}"
echo "  ${CHECKSUMS_PATH}"
echo ""
echo "Version: ${VERSION}"
echo "SHA256: ${SHA256}"
echo ""
echo "Upload these assets to the GitHub release tagged ${VERSION}:"
echo "  ${ZIP_NAME}"
echo "  checksums.txt"
