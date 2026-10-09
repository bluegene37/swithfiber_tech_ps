#!/usr/bin/env bash
# Gene - Oct 09, 2026: Terminal dispatch script to manually trigger iOS (TestFlight), Android (Play Store), and unified Release CI/CD workflows via release.yml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

show_help() {
  cat << 'EOF'
Usage: ./scripts/deploy.sh [COMMAND] [OPTIONS]

Unified release & deployment dispatcher via GitHub Actions ('release.yml').

Commands:
  all                  Deploy both Apple TestFlight and Google Play (Closed Testing)
  all-internal         Deploy both Apple TestFlight and Google Play (Internal Testing)
  ios                  Deploy only to Apple TestFlight
  android              Deploy only to Google Play Closed Testing (alpha track default)
  android-internal     Deploy only to Google Play Internal Testing (internal track)
  ci                   Run static analysis, formatting, and unit tests (ci.yml)
  local-ios            Build and upload iOS IPA locally using ./scripts/deploy_testflight.sh
  status               Check status of recent GitHub Actions workflow runs

Options:
  -w, --watch          Follow live workflow logs in the terminal after dispatching
  -h, --help           Show this help message

Direct 'gh' CLI equivalents:
  gh workflow run release.yml -f platform=all
  gh workflow run release.yml -f platform=ios
  gh workflow run release.yml -f platform=android
  gh workflow run release.yml -f platform=android -f track=internal
EOF
}

check_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: GitHub CLI ('gh') is not installed or not in PATH."
    echo "Install it with 'brew install gh' and authenticate with 'gh auth login'."
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: GitHub CLI is not authenticated. Run 'gh auth login' first."
    exit 1
  fi
}

dispatch_workflow() {
  local workflow="$1"
  shift
  local extra_args=("$@")

  check_gh
  echo "🚀 Dispatching GitHub Actions workflow: $workflow ${extra_args[*]:-}..."
  gh workflow run "$workflow" "${extra_args[@]}"
  echo "✅ Workflow dispatched successfully!"
  sleep 3

  local latest_run_id
  latest_run_id=$(gh run list --workflow="$workflow" -L 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)

  if [ -n "$latest_run_id" ]; then
    echo "🔗 Run details: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/runs/$latest_run_id"
  fi

  if [ "$WATCH_LOGS" = true ] && [ -n "$latest_run_id" ]; then
    echo "📡 Watching run $latest_run_id..."
    gh run watch "$latest_run_id"
  fi
}

WATCH_LOGS=false
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -w|--watch)
      WATCH_LOGS=true
      shift
      ;;
    all|all-internal|ios|android|android-internal|ci|local-ios|status)
      TARGET="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "=================================================="
  echo "   Switch Fiber Tech - Unified Release Dispatch   "
  echo "=================================================="
  echo "1) Both Apple TestFlight & Google Play (Closed Testing / alpha)"
  echo "2) Both Apple TestFlight & Google Play (Internal Testing)"
  echo "3) Apple TestFlight only"
  echo "4) Google Play Closed Testing only (alpha default)"
  echo "5) Google Play Internal Testing only (internal track)"
  echo "6) CI Checks (Analyze & Test)"
  echo "7) Local iOS Build & Upload (deploy_testflight.sh)"
  echo "8) Check recent workflow statuses"
  echo "9) Exit"
  echo ""
  read -r -p "Select an option [1-9]: " CHOICE

  case "$CHOICE" in
    1) TARGET="all" ;;
    2) TARGET="all-internal" ;;
    3) TARGET="ios" ;;
    4) TARGET="android" ;;
    5) TARGET="android-internal" ;;
    6) TARGET="ci" ;;
    7) TARGET="local-ios" ;;
    8) TARGET="status" ;;
    9) exit 0 ;;
    *) echo "Invalid choice."; exit 1 ;;
  esac
fi

case "$TARGET" in
  all)
    dispatch_workflow "release.yml" -f platform=all
    ;;
  all-internal)
    dispatch_workflow "release.yml" -f platform=all -f track=internal
    ;;
  ios)
    dispatch_workflow "release.yml" -f platform=ios
    ;;
  android)
    dispatch_workflow "release.yml" -f platform=android
    ;;
  android-internal)
    dispatch_workflow "release.yml" -f platform=android -f track=internal
    ;;
  ci)
    dispatch_workflow "ci.yml"
    ;;
  local-ios)
    "${PROJECT_ROOT}/scripts/deploy_testflight.sh"
    ;;
  status)
    check_gh
    gh run list -L 10
    ;;
esac
