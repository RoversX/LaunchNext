#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/LaunchNext.xcodeproj"
SCHEME="LaunchNext"
CONFIGURATION="Release"

TEAM_ID="${LAUNCHNEXT_TEAM_ID:-}"
NOTARY_PROFILE="${LAUNCHNEXT_NOTARY_PROFILE:-LaunchNext-notary}"
POLL_INTERVAL_SECONDS="${LAUNCHNEXT_NOTARY_POLL_INTERVAL_SECONDS:-30}"
RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RELEASE_ROOT="${LAUNCHNEXT_NOTARIZED_BUILD_DIR:-${ROOT_DIR}/build/notarized-release-${RUN_ID}}"
RESUME_MODE="NO"
MODE=""
LOCAL_INPUT_PATH=""

usage() {
  cat <<'EOF'
Create a Developer ID-signed, notarized LaunchNext release.

Usage:
  ./scripts/release-notarized.sh [options]

Options:
  --notarize              build, upload to Apple, and notarize using the CLI
  --local PATH            use an existing local .app or .zip
  --keychain-profile NAME  notarytool Keychain profile (default: LaunchNext-notary)
  --team-id TEAM_ID        override automatic Apple Developer Team detection
  --output-dir PATH        generated archive, exported app, logs, and release assets
  --resume PATH            resume an existing submission without rebuilding or re-uploading
  -h, --help               show this help

One-time local setup (credentials are stored in macOS Keychain, not this repo):
  xcrun notarytool store-credentials "LaunchNext-notary" \
    --apple-id "YOUR_APPLE_ID" \
    --team-id "YOUR_TEAM_ID"

The command securely prompts for an app-specific password when --password is
omitted. You can also create the profile with an App Store Connect API key; see
`xcrun notarytool store-credentials --help`.
EOF
}

KEYCHAIN_TEAM_IDS=()

load_keychain_team_ids() {
  KEYCHAIN_TEAM_IDS=()

  local identity_line candidate_team existing_team already_added
  while IFS= read -r identity_line; do
    [[ "${identity_line}" == *'"Developer ID Application:'* ]] || continue

    candidate_team="$(printf '%s\n' "${identity_line}" | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p')"
    [[ -n "${candidate_team}" ]] || continue

    already_added="NO"
    for existing_team in "${KEYCHAIN_TEAM_IDS[@]-}"; do
      if [[ "${existing_team}" == "${candidate_team}" ]]; then
        already_added="YES"
        break
      fi
    done

    if [[ "${already_added}" == "NO" ]]; then
      KEYCHAIN_TEAM_IDS+=("${candidate_team}")
    fi
  done < <(security find-identity -v -p codesigning 2>/dev/null || true)
}

resolve_team_id_from_keychain() {
  [[ -z "${TEAM_ID}" ]] || return

  load_keychain_team_ids

  case "${#KEYCHAIN_TEAM_IDS[@]}" in
    1)
      TEAM_ID="${KEYCHAIN_TEAM_IDS[0]}"
      echo "Using Apple Developer Team ${TEAM_ID} from the macOS Keychain."
      ;;
    0)
      echo "error: no valid 'Developer ID Application' identity was found in the macOS Keychain." >&2
      echo "Install the release certificate, or provide the team for this run with --team-id." >&2
      exit 1
      ;;
    *)
      echo "error: multiple Apple Developer teams are available in the macOS Keychain:" >&2
      printf '  %s\n' "${KEYCHAIN_TEAM_IDS[@]}" >&2
      echo "Choose one for this run with --team-id TEAM_ID." >&2
      exit 1
      ;;
  esac
}

select_mode() {
  local requested_mode="$1"
  if [[ -n "${MODE}" && "${MODE}" != "${requested_mode}" ]]; then
    echo "error: choose only one of --notarize, --local, or --resume" >&2
    exit 2
  fi
  MODE="${requested_mode}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notarize)
      select_mode "notarize"
      shift
      ;;
    --local)
      [[ $# -ge 2 ]] || { echo "error: --local requires a value" >&2; exit 2; }
      select_mode "local"
      LOCAL_INPUT_PATH="$2"
      shift 2
      ;;
    --keychain-profile)
      [[ $# -ge 2 ]] || { echo "error: --keychain-profile requires a value" >&2; exit 2; }
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --team-id)
      [[ $# -ge 2 ]] || { echo "error: --team-id requires a value" >&2; exit 2; }
      TEAM_ID="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { echo "error: --output-dir requires a value" >&2; exit 2; }
      RELEASE_ROOT="$2"
      shift 2
      ;;
    --resume)
      [[ $# -ge 2 ]] || { echo "error: --resume requires a value" >&2; exit 2; }
      select_mode "resume"
      RELEASE_ROOT="$2"
      RESUME_MODE="YES"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${MODE}" ]]; then
  if [[ ! -t 0 ]]; then
    echo "error: interactive input is unavailable; use --notarize or --local PATH" >&2
    exit 2
  fi

  echo "Select a release source:"
  echo "  1) Build, upload to Apple, and notarize"
  echo "  2) Use an existing local .app or .zip"
  printf "Choice [1-2]: "
  IFS= read -r RELEASE_CHOICE

  case "${RELEASE_CHOICE}" in
    1)
      MODE="notarize"
      ;;
    2)
      MODE="local"
      printf "Drag a local .app or .zip here, then press Return: "
      IFS= read -e LOCAL_INPUT_PATH
      LOCAL_INPUT_PATH="${LOCAL_INPUT_PATH#\"}"
      LOCAL_INPUT_PATH="${LOCAL_INPUT_PATH%\"}"
      LOCAL_INPUT_PATH="${LOCAL_INPUT_PATH#\'}"
      LOCAL_INPUT_PATH="${LOCAL_INPUT_PATH%\'}"
      ;;
    *)
      echo "error: invalid choice" >&2
      exit 2
      ;;
  esac
fi

for tool in xcodebuild xcrun swift codesign spctl ditto lipo plutil shasum security; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: required tool not found: ${tool}" >&2
    exit 1
  fi
done

if [[ "${RESUME_MODE}" == "NO" && -e "${RELEASE_ROOT}" ]]; then
  echo "error: output directory already exists: ${RELEASE_ROOT}" >&2
  echo "Choose another path with --output-dir." >&2
  exit 1
fi

if [[ "${RESUME_MODE}" == "YES" && ! -d "${RELEASE_ROOT}" ]]; then
  echo "error: resume directory does not exist: ${RELEASE_ROOT}" >&2
  exit 1
fi

if [[ ! "${POLL_INTERVAL_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: LAUNCHNEXT_NOTARY_POLL_INTERVAL_SECONDS must be a positive integer" >&2
  exit 1
fi

if [[ -n "${TEAM_ID}" && ! "${TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "error: Apple Developer Team ID must contain 10 uppercase letters or digits" >&2
  exit 1
fi

if [[ "${MODE}" == "notarize" ]]; then
  resolve_team_id_from_keychain
fi

if [[ "${MODE}" != "local" ]]; then
  echo "Checking notarization credentials in macOS Keychain..."
  if ! xcrun notarytool history \
    --keychain-profile "${NOTARY_PROFILE}" \
    --output-format json >/dev/null 2>&1; then
    echo "error: notarytool could not use Keychain profile '${NOTARY_PROFILE}'." >&2
    echo "Create it once with:" >&2
    echo "  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id \"YOUR_APPLE_ID\" --team-id \"${TEAM_ID:-YOUR_TEAM_ID}\"" >&2
    exit 1
  fi
fi

ARCHIVE_PATH="${RELEASE_ROOT}/LaunchNext.xcarchive"
DERIVED_DATA_PATH="${RELEASE_ROOT}/DerivedData"
EXPORT_PATH="${RELEASE_ROOT}/export"
DIST_PATH="${RELEASE_ROOT}/dist"
EXPORT_OPTIONS_PATH="${RELEASE_ROOT}/ExportOptions.plist"
NOTARY_SUBMISSION_PATH="${RELEASE_ROOT}/LaunchNext-notary-submission.zip"
NOTARY_RESULT_PATH="${RELEASE_ROOT}/notary-result.json"
NOTARY_STATUS_PATH="${RELEASE_ROOT}/notary-status.json"
NOTARY_LOG_PATH="${RELEASE_ROOT}/notary-log.json"
LOCAL_EXTRACT_PATH="${RELEASE_ROOT}/local-extract"
LOCAL_ZIP_SOURCE=""
LOCAL_ZIP_REQUIRES_REPACK="NO"
SUBMISSION_ID=""

if [[ "${MODE}" != "resume" ]]; then
  mkdir -p "${RELEASE_ROOT}" "${EXPORT_PATH}" "${DIST_PATH}"
fi

if [[ "${MODE}" == "notarize" ]]; then
  echo "Building the universal SwiftUpdater..."
  swift build \
    --package-path "${ROOT_DIR}/UpdaterScripts/SwiftUpdater" \
    --configuration release \
    --arch arm64 \
    --arch x86_64 \
    --product SwiftUpdater

  echo "Creating the Xcode archive..."
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE_PATH}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -allowProvisioningUpdates \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    clean archive

  plutil -create xml "${EXPORT_OPTIONS_PATH}"
  plutil -insert method -string developer-id "${EXPORT_OPTIONS_PATH}"
  plutil -insert destination -string export "${EXPORT_OPTIONS_PATH}"
  plutil -insert signingStyle -string automatic "${EXPORT_OPTIONS_PATH}"
  plutil -insert teamID -string "${TEAM_ID}" "${EXPORT_OPTIONS_PATH}"

  echo "Exporting with Developer ID signing..."
  xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PATH}" \
    -allowProvisioningUpdates
fi

APP_PATH="${EXPORT_PATH}/LaunchNext.app"
UPDATER_PATH="${APP_PATH}/Contents/Resources/Updater/SwiftUpdater"

if [[ "${MODE}" == "local" ]]; then
  while [[ "${LOCAL_INPUT_PATH}" == [[:space:]]* ]]; do
    LOCAL_INPUT_PATH="${LOCAL_INPUT_PATH#?}"
  done
  while [[ "${LOCAL_INPUT_PATH}" == *[[:space:]] ]]; do
    LOCAL_INPUT_PATH="${LOCAL_INPUT_PATH%?}"
  done
  LOCAL_INPUT_PATH="${LOCAL_INPUT_PATH%/}"

  if [[ -d "${LOCAL_INPUT_PATH}" && "${LOCAL_INPUT_PATH}" == *.app ]]; then
    echo "Copying the local app without modifying the original..."
    ditto "${LOCAL_INPUT_PATH}" "${APP_PATH}"
  elif [[ -f "${LOCAL_INPUT_PATH}" && ( "${LOCAL_INPUT_PATH}" == *.zip || "${LOCAL_INPUT_PATH}" == *.ZIP ) ]]; then
    echo "Extracting the local ZIP for verification..."
    mkdir -p "${LOCAL_EXTRACT_PATH}"
    ditto -x -k "${LOCAL_INPUT_PATH}" "${LOCAL_EXTRACT_PATH}"

    LOCAL_APP_CANDIDATES=()
    while IFS= read -r -d '' LOCAL_APP_CANDIDATE; do
      LOCAL_APP_CANDIDATES+=("${LOCAL_APP_CANDIDATE}")
    done < <(find "${LOCAL_EXTRACT_PATH}" -maxdepth 4 -type d -name 'LaunchNext.app' -print0)

    if [[ ${#LOCAL_APP_CANDIDATES[@]} -ne 1 ]]; then
      echo "error: expected exactly one LaunchNext.app in ${LOCAL_INPUT_PATH}" >&2
      exit 1
    fi

    ditto "${LOCAL_APP_CANDIDATES[0]}" "${APP_PATH}"
    LOCAL_ZIP_SOURCE="${LOCAL_INPUT_PATH}"
  else
    echo "error: local input must be an existing .app or .zip: ${LOCAL_INPUT_PATH}" >&2
    exit 1
  fi
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: exported app not found at ${APP_PATH}" >&2
  exit 1
fi

if [[ ! -x "${UPDATER_PATH}" ]]; then
  echo "error: bundled SwiftUpdater not found at ${UPDATER_PATH}" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
APP_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP_PATH}/Contents/Info.plist")"

if [[ "${BUNDLE_ID}" != "com.roversx.launchnext" ]]; then
  echo "error: unexpected bundle identifier: ${BUNDLE_ID}" >&2
  exit 1
fi

if [[ -z "${VERSION}" ]]; then
  echo "error: could not read CFBundleShortVersionString" >&2
  exit 1
fi

if [[ -z "${APP_EXECUTABLE_NAME}" || "${APP_EXECUTABLE_NAME}" == */* ]]; then
  echo "error: invalid or missing CFBundleExecutable" >&2
  exit 1
fi

APP_EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/${APP_EXECUTABLE_NAME}"

require_release_architectures() {
  local binary_path="$1"
  local binary_label="$2"
  local architectures required_architecture

  if [[ ! -x "${binary_path}" ]]; then
    echo "error: ${binary_label} executable not found at ${binary_path}" >&2
    exit 1
  fi

  if ! architectures="$(lipo -archs "${binary_path}" 2>/dev/null)"; then
    echo "error: ${binary_label} is not a valid Mach-O executable" >&2
    exit 1
  fi

  for required_architecture in arm64 x86_64; do
    if [[ " ${architectures} " != *" ${required_architecture} "* ]]; then
      echo "error: ${binary_label} is missing required architecture ${required_architecture} (found: ${architectures})" >&2
      exit 1
    fi
  done

  echo "${binary_label} architectures: ${architectures}"
}

echo "Verifying universal binary architectures..."
require_release_architectures "${APP_EXECUTABLE_PATH}" "LaunchNext"
require_release_architectures "${UPDATER_PATH}" "SwiftUpdater"

echo "Verifying Developer ID signatures..."
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

APP_SIGNATURE="$(codesign -d --verbose=4 "${APP_PATH}" 2>&1)"
UPDATER_SIGNATURE="$(codesign -d --verbose=4 "${UPDATER_PATH}" 2>&1)"

APP_TEAM_ID="$(printf '%s\n' "${APP_SIGNATURE}" | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')"
UPDATER_TEAM_ID="$(printf '%s\n' "${UPDATER_SIGNATURE}" | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')"

if [[ -z "${APP_TEAM_ID}" || -z "${UPDATER_TEAM_ID}" ]]; then
  echo "error: LaunchNext and SwiftUpdater must both contain a Developer ID team identifier" >&2
  exit 1
fi

if [[ -z "${TEAM_ID}" ]]; then
  TEAM_ID="${APP_TEAM_ID}"
  echo "Using Apple Developer Team ${TEAM_ID} from the signed app."
fi

if [[ "${APP_TEAM_ID}" != "${TEAM_ID}" ]]; then
  echo "error: LaunchNext is not signed by expected team ${TEAM_ID}" >&2
  exit 1
fi

if [[ "${UPDATER_TEAM_ID}" != "${TEAM_ID}" ]]; then
  echo "error: SwiftUpdater is not signed by expected team ${TEAM_ID}" >&2
  exit 1
fi

if [[ "${APP_SIGNATURE}" != *"runtime"* || "${UPDATER_SIGNATURE}" != *"runtime"* ]]; then
  echo "error: LaunchNext and SwiftUpdater must both use Hardened Runtime" >&2
  exit 1
fi

if [[ "${MODE}" != "local" ]]; then
  if [[ "${MODE}" == "notarize" ]]; then
    echo "Preparing notarization submission..."
    ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${NOTARY_SUBMISSION_PATH}"

    echo "Submitting to Apple's notary service..."
    if ! xcrun notarytool submit "${NOTARY_SUBMISSION_PATH}" \
      --keychain-profile "${NOTARY_PROFILE}" \
      --no-wait \
      --output-format json >"${NOTARY_RESULT_PATH}"; then
      cat "${NOTARY_RESULT_PATH}" >&2 || true
      echo "error: notarization upload failed" >&2
      exit 1
    fi

    cat "${NOTARY_RESULT_PATH}"
  elif [[ ! -s "${NOTARY_RESULT_PATH}" ]]; then
    echo "error: submission record not found: ${NOTARY_RESULT_PATH}" >&2
    exit 1
  fi

  SUBMISSION_ID="$(plutil -extract id raw -o - "${NOTARY_RESULT_PATH}" 2>/dev/null || true)"

  if [[ -z "${SUBMISSION_ID}" ]]; then
    echo "error: notarization submission ID is missing from ${NOTARY_RESULT_PATH}" >&2
    exit 1
  fi

  print_resume_hint() {
    echo
    echo "Apple will continue processing submission ${SUBMISSION_ID}."
    echo "Resume this release later with:"
    printf '  %q --resume %q --keychain-profile %q\n' "$0" "${RELEASE_ROOT}" "${NOTARY_PROFILE}"
  }

  handle_poll_interruption() {
    print_resume_hint
    exit 130
  }

  trap handle_poll_interruption HUP INT TERM

  echo "Submission ID saved: ${SUBMISSION_ID}"
  echo "Waiting for Apple; status will be checked every ${POLL_INTERVAL_SECONDS} seconds."

  while true; do
    if ! xcrun notarytool info "${SUBMISSION_ID}" \
      --keychain-profile "${NOTARY_PROFILE}" \
      --output-format json >"${NOTARY_STATUS_PATH}"; then
      echo "Status check failed; Apple may still be processing. Retrying in ${POLL_INTERVAL_SECONDS} seconds..." >&2
      sleep "${POLL_INTERVAL_SECONDS}"
      continue
    fi

    NOTARY_STATUS="$(plutil -extract status raw -o - "${NOTARY_STATUS_PATH}" 2>/dev/null || true)"

    case "${NOTARY_STATUS}" in
      Accepted)
        cat "${NOTARY_STATUS_PATH}"
        break
        ;;
      "In Progress")
        echo "$(date '+%Y-%m-%d %H:%M:%S')  Notarization is still in progress..."
        sleep "${POLL_INTERVAL_SECONDS}"
        ;;
      Invalid|Rejected)
        cat "${NOTARY_STATUS_PATH}" >&2
        xcrun notarytool log "${SUBMISSION_ID}" \
          --keychain-profile "${NOTARY_PROFILE}" \
          "${NOTARY_LOG_PATH}" || true
        echo "Notarization log: ${NOTARY_LOG_PATH}" >&2
        echo "error: notarization was not accepted" >&2
        exit 1
        ;;
      *)
        cat "${NOTARY_STATUS_PATH}" >&2
        echo "error: unexpected notarization status: ${NOTARY_STATUS:-missing}" >&2
        print_resume_hint >&2
        exit 1
        ;;
    esac
  done

  trap - HUP INT TERM

  echo "Stapling and validating the notarization ticket..."
  xcrun stapler staple "${APP_PATH}"
else
  echo "Validating the local notarization ticket..."
  if ! xcrun stapler validate "${APP_PATH}"; then
    echo "The local copy has no stapled ticket; attempting to staple its existing Apple ticket..."
    xcrun stapler staple "${APP_PATH}"
    LOCAL_ZIP_REQUIRES_REPACK="YES"
  fi
fi

xcrun stapler validate "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
spctl --assess --type execute --verbose=4 "${APP_PATH}"

ZIP_NAME="LaunchNext${VERSION}.zip"
ZIP_PATH="${DIST_PATH}/${ZIP_NAME}"
CHECKSUMS_PATH="${DIST_PATH}/checksums.txt"

echo "Creating GitHub Release assets..."
mkdir -p "${DIST_PATH}"
if [[ "${MODE}" == "local" && -n "${LOCAL_ZIP_SOURCE}" && "${LOCAL_ZIP_REQUIRES_REPACK}" == "NO" ]]; then
  echo "Keeping the exact bytes of the verified local ZIP."
  cp -p "${LOCAL_ZIP_SOURCE}" "${ZIP_PATH}"
else
  ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
fi

(
  cd "${DIST_PATH}"
  shasum -a 256 "${ZIP_NAME}" >"${CHECKSUMS_PATH}"
)

SHA256="$(awk '{print $1}' "${CHECKSUMS_PATH}")"

echo
echo "Notarized release artifacts:"
echo "  ${ZIP_PATH}"
echo "  ${CHECKSUMS_PATH}"
echo
echo "Version: ${VERSION}"
echo "SHA256: ${SHA256}"
if [[ -n "${SUBMISSION_ID}" ]]; then
  echo "Notary submission: ${SUBMISSION_ID}"
fi
echo
echo "Upload these assets to the GitHub release:"
echo "  ${ZIP_NAME}"
echo "  checksums.txt"
