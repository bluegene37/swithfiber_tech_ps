#!/usr/bin/env bash
# Gene - Oct 09, 2026: Terminal dispatch script to manually trigger iOS (TestFlight), Android (Play Store), and Release CI/CD workflows on demand.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

show_help() {
  cat << 'EOF'
Usage: ./scripts/deploy.sh [COMMAND] [OPTIONS]

Trigger cloud CI/CD deployments or local release builds from your terminal.

Commands:
  ios          Deploy iOS app to Apple TestFlight via GitHub Actions
  android      Deploy Android App Bundle to Google Play Internal Testing via GitHub Actions
  all          Deploy both iOS & Android via GitHub Actions Release workflow
  ci           Run static analysis, formatting, and unit tests via GitHub Actions
  local-ios    Build and upload iOS IPA locally using ./scripts/deploy_testflight.sh
  status       Check status of recent GitHub Actions workflow runs

Options:
  -w, --watch  Follow live workflow logs in the terminal after dispatching
  -h, --help   Show this help message

Examples:
  ./scripts/deploy.sh ios              # Trigger TestFlight deployment in GitHub Actions
  ./scripts/deploy.sh android --watch  # Trigger Play Store deployment and stream logs
  ./scripts/deploy.sh all              # Trigger both iOS and Android releases
  ./scripts/deploy.sh status           # View recent workflow runs
  ./scripts/deploy.sh                  # Interactive menu
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
  echo "🚀 Dispatching GitHub Actions workflow: $workflow..."
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
    ios|android|all|ci|local-ios|status)
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
  echo "  Switch Fiber Tech - Deployment & CI Dispatcher  "
  echo "=================================================="
  echo "1) iOS (Apple TestFlight via GitHub Actions)"
  echo "2) Android (Google Play Internal via GitHub Actions)"
  echo "3) Both iOS & Android (GitHub Actions Release)"
  echo "4) CI Checks (Analyze & Test via GitHub Actions)"
  echo "5) Local iOS Build & Upload (deploy_testflight.sh)"
  echo "6) Check workflow status"
  echo "7) Exit"
  echo ""
  read -r -p "Select an option [1-7]: " CHOICE

  case "$CHOICE" in
    1) TARGET="ios" ;;
    2) TARGET="android" ;;
    3) TARGET="all" ;;
    4) TARGET="ci" ;;
    5) TARGET="local-ios" ;;
    6) TARGET="status" ;;
    7) exit 0 ;;
    *) echo "Invalid choice."; exit 1 ;;
  esac
fi

case "$TARGET" in
  ios)
    dispatch_workflow "deploy-testflight.yml"
    ;;
  android)
    dispatch_workflow "deploy-internal.yml"
    ;;
  all)
    dispatch_workflow "release.yml" -f platform=all -f track=internal
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
