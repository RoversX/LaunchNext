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

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign -dv --verbose=2 "${APP_PATH}" 2>&1 | sed -n '1,24p'

echo "Checking Gatekeeper distribution status..."
SYSPOLICY_LOG="$(mktemp)"
if ! command -v syspolicy_check >/dev/null 2>&1; then
  echo "warning: syspolicy_check is unavailable on this macOS installation; skipping distribution preflight."
elif syspolicy_check distribution "${APP_PATH}" >"${SYSPOLICY_LOG}" 2>&1; then
  cat "${SYSPOLICY_LOG}"
else
  cat "${SYSPOLICY_LOG}"
  if grep -q "Adhoc Signed App" "${SYSPOLICY_LOG}" && grep -q "Notary Ticket Missing" "${SYSPOLICY_LOG}"; then
    echo "warning: app is ad-hoc signed and not notarized. This is acceptable for unsigned community builds; users must approve it in System Settings > Privacy & Security."
  else
    echo "error: Gatekeeper reported an unexpected distribution issue." >&2
    exit 1
  fi
fi
rm -f "${SYSPOLICY_LOG}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
if [[ -z "${VERSION}" ]]; then
  echo "error: Could not read CFBundleShortVersionString from ${APP_PATH}" >&2
  exit 1
fi

ZIP_NAME="LaunchNext${VERSION}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
CHECKSUMS_PATH="${RELEASE_DIR}/checksums.txt"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

VERIFY_DIR="$(mktemp -d)"
ditto -x -k "${ZIP_PATH}" "${VERIFY_DIR}"
codesign --verify --deep --strict --verbose=2 "${VERIFY_DIR}/LaunchNext.app"

SPCTL_LOG="$(mktemp)"
if spctl -a -vvv -t exec "${VERIFY_DIR}/LaunchNext.app" >"${SPCTL_LOG}" 2>&1; then
  cat "${SPCTL_LOG}"
else
  cat "${SPCTL_LOG}"
  if grep -q "rejected" "${SPCTL_LOG}"; then
    echo "warning: Gatekeeper rejects this unsigned, non-notarized build. This should show the normal Privacy & Security approval path, not a damaged-app error."
  else
    echo "error: unexpected spctl result after zip round-trip." >&2
    exit 1
  fi
fi
rm -f "${SPCTL_LOG}"
rm -rf "${VERIFY_DIR}"

(
  cd "${RELEASE_DIR}"
  shasum -a 256 "${ZIP_NAME}" > "${CHECKSUMS_PATH}"
)

SHA256="$(awk '{print $1}' "${CHECKSUMS_PATH}")"

echo "Release artifacts:"
echo "  ${ZIP_PATH}"
echo "  ${CHECKSUMS_PATH}"
echo ""
echo "Version: ${VERSION}"
echo "SHA256: ${SHA256}"
echo ""
echo "Upload these assets to the GitHub release tagged ${VERSION}:"
echo "  ${ZIP_NAME}"
echo "  checksums.txt"
