#!/usr/bin/env bash
# Gene - Oct 08, 2026: Local automation script for building obfuscated iOS IPA and deploying to Apple TestFlight.
set -euo pipefail

show_help() {
  cat << 'EOF'
Usage: ./scripts/deploy_testflight.sh [OPTIONS]

Local automation script for building obfuscated iOS IPA and deploying to Apple TestFlight.

Options:
  -h, --help               Display this help message and exit
  --build-number <num>     Override the build number (integer, e.g. 42)
  --skip-tests             Skip static analysis and unit tests
  --skip-upload            Build the IPA and archive symbols, but skip upload to TestFlight
  --api-key <key-id>       App Store Connect API Key ID (defaults to $APP_STORE_CONNECT_KEY_ID)
  --api-issuer <uuid>      App Store Connect Issuer ID (defaults to $APP_STORE_CONNECT_ISSUER_ID)

Environment Variables:
  APP_STORE_CONNECT_KEY_ID      Fallback for --api-key
  APP_STORE_CONNECT_ISSUER_ID   Fallback for --api-issuer

Prerequisites:
  - Flutter SDK (flutter CLI)
  - Xcode & Command Line Tools (xcodebuild, xcrun)
  - Valid Apple Distribution certificate and profile installed in Keychain
  - ios/ExportOptions.plist configured for app-store distribution
  - App Store Connect API Key (.p8) in ~/.appstoreconnect/private_keys or ~/.private_keys (for automated upload)

Examples:
  # Build and upload using environment variables:
  ./scripts/deploy_testflight.sh

  # Build with explicit build number and API credentials:
  ./scripts/deploy_testflight.sh --build-number 105 --api-key ABCD1234EF --api-issuer 69a6de70-xxxx-xxxx-xxxx-xxxxxxxxxxxx

  # Build IPA only (for manual Apple Transporter upload):
  ./scripts/deploy_testflight.sh --skip-upload

  # Quick build skipping tests (development only):
  ./scripts/deploy_testflight.sh --skip-tests --skip-upload
EOF
}

# Ensure script operates from repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

BUILD_NUMBER=""
SKIP_TESTS=false
SKIP_UPLOAD=false
API_KEY="${APP_STORE_CONNECT_KEY_ID:-}"
API_ISSUER="${APP_STORE_CONNECT_ISSUER_ID:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --build-number)
      if [[ -z "${2:-}" || "${2:-}" =~ ^- ]]; then
        echo "Error: --build-number requires a value." >&2
        exit 1
      fi
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --build-number=*)
      BUILD_NUMBER="${1#*=}"
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    --skip-upload)
      SKIP_UPLOAD=true
      shift
      ;;
    --api-key)
      if [[ -z "${2:-}" || "${2:-}" =~ ^- ]]; then
        echo "Error: --api-key requires a value." >&2
        exit 1
      fi
      API_KEY="$2"
      shift 2
      ;;
    --api-key=*)
      API_KEY="${1#*=}"
      shift
      ;;
    --api-issuer)
      if [[ -z "${2:-}" || "${2:-}" =~ ^- ]]; then
        echo "Error: --api-issuer requires a value." >&2
        exit 1
      fi
      API_ISSUER="$2"
      shift 2
      ;;
    --api-issuer=*)
      API_ISSUER="${1#*=}"
      shift
      ;;
    *)
      echo "Error: Unknown option '$1'" >&2
      echo "Run '$0 --help' for usage instructions." >&2
      exit 1
      ;;
  esac
done

# Step 1: Validate prerequisites
echo "==> Step 1/5: Validating prerequisites..."
for cmd in flutter xcodebuild xcrun; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Required command '$cmd' is not installed or not in PATH." >&2
    exit 1
  fi
done

if [[ ! -f "ios/ExportOptions.plist" ]]; then
  echo "Error: Required export options file 'ios/ExportOptions.plist' not found." >&2
  exit 1
fi
echo "Prerequisites verified."

# Step 2: Static analysis & test suite
if [[ "$SKIP_TESTS" == "true" ]]; then
  echo "==> Step 2/5: Skipping analysis and tests (--skip-tests specified)."
else
  echo "==> Step 2/5: Running static analysis and tests..."
  echo "--> Running flutter analyze --fatal-infos..."
  flutter analyze --fatal-infos
  echo "--> Running flutter test..."
  flutter test
fi

# Step 3: Build release IPA
echo "==> Step 3/5: Building release iOS IPA with obfuscation..."
mkdir -p build/symbols/ios

BUILD_CMD=(flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios --export-options-plist=ios/ExportOptions.plist)
if [[ -n "$BUILD_NUMBER" ]]; then
  BUILD_CMD+=(--build-number="$BUILD_NUMBER")
fi

echo "--> Executing: ${BUILD_CMD[*]}"
"${BUILD_CMD[@]}"

# Step 4: Archive debug symbols
echo "==> Step 4/5: Archiving debug symbols..."
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SYMBOL_ARCHIVE="build/symbols-ios-${TIMESTAMP}.tar.gz"

if [[ -d "build/symbols/ios" ]]; then
  tar -czf "${SYMBOL_ARCHIVE}" -C build/symbols ios
  echo "Symbols archive created: ${SYMBOL_ARCHIVE}"
else
  echo "Warning: build/symbols/ios directory not found; skipping symbol archive."
fi

# Step 5: Resolve IPA and upload
echo "==> Step 5/5: Resolving IPA artifact and upload..."
IPA_PATH=$(find build/ios/ipa -name "*.ipa" -print -quit 2>/dev/null || true)

if [[ -z "$IPA_PATH" || ! -f "$IPA_PATH" ]]; then
  echo "Error: No .ipa artifact found in build/ios/ipa." >&2
  exit 1
fi
echo "IPA artifact found: ${IPA_PATH}"

if [[ "$SKIP_UPLOAD" == "true" ]]; then
  echo ""
  echo "================================================================================"
  echo "Build completed successfully! Upload skipped (--skip-upload)."
  echo "  IPA Location:     ${IPA_PATH}"
  if [[ -f "${SYMBOL_ARCHIVE:-}" ]]; then
    echo "  Symbols Archive:  ${SYMBOL_ARCHIVE}"
  fi
  echo "================================================================================"
  exit 0
fi

if [[ -n "$API_KEY" && -n "$API_ISSUER" ]]; then
  echo "--> Uploading IPA to TestFlight via xcrun altool..."
  
  KEY_FILE_FOUND=false
  for key_dir in "$HOME/.appstoreconnect/private_keys" "$HOME/.private_keys" "$HOME/private_keys" "./private_keys"; do
    if [[ -f "${key_dir}/AuthKey_${API_KEY}.p8" ]]; then
      KEY_FILE_FOUND=true
      break
    fi
  done

  if [[ "$KEY_FILE_FOUND" == "false" ]]; then
    echo "Warning: AuthKey_${API_KEY}.p8 was not found in standard directories (~/.appstoreconnect/private_keys, ~/.private_keys)."
    echo "If xcrun altool fails, verify that your .p8 key is at ~/.appstoreconnect/private_keys/AuthKey_${API_KEY}.p8"
  fi

  xcrun altool --upload-app \
    -f "$IPA_PATH" \
    -t ios \
    --apiKey "$API_KEY" \
    --apiIssuer "$API_ISSUER"

  echo ""
  echo "================================================================================"
  echo "TestFlight upload completed successfully!"
  echo "  IPA Location:     ${IPA_PATH}"
  if [[ -f "${SYMBOL_ARCHIVE:-}" ]]; then
    echo "  Symbols Archive:  ${SYMBOL_ARCHIVE}"
  fi
  echo "================================================================================"
else
  echo ""
  echo "================================================================================"
  echo "Build completed successfully! Ready for TestFlight distribution."
  echo "  IPA Location:     ${IPA_PATH}"
  if [[ -f "${SYMBOL_ARCHIVE:-}" ]]; then
    echo "  Symbols Archive:  ${SYMBOL_ARCHIVE}"
  fi
  echo ""
  echo "App Store Connect API credentials were not provided."
  echo "To upload automatically using xcrun altool, provide API credentials:"
  echo "  $0 --api-key <KEY_ID> --api-issuer <ISSUER_UUID>"
  echo "  or export APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID in your shell."
  echo ""
  echo "Manual upload using Apple Transporter app:"
  echo "  1. Download and open 'Transporter' from the Mac App Store."
  echo "  2. Sign in with your Apple Developer credentials."
  echo "  3. Drag and drop '${IPA_PATH}' into Transporter."
  echo "  4. Click 'Deliver' to upload the package to TestFlight."
  echo "================================================================================"
fi
