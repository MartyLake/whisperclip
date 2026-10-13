#!/usr/bin/env bash
set -euo pipefail

# Generates Xcode/WhisperClip.xcodeproj from project.yml (app target, not the Swift package).
#
#   ./xcode_gen.sh          # generate
#   ./xcode_gen.sh --open   # generate and open in Xcode
#
# Signing defaults to ad-hoc ("-"). macOS then forgets microphone / accessibility grants on
# every rebuild; to keep them, sign with a stable identity:
#   WHISPERCLIP_CODE_SIGN_IDENTITY="Apple Development" WHISPERCLIP_TEAM_ID=XXXXXXXXXX ./xcode_gen.sh

cd "$(dirname "$0")"

command -v xcodegen >/dev/null || { echo "Error: xcodegen not found (brew install xcodegen)" >&2; exit 1; }

PROJECT_DIR="Xcode"
PROJECT="$PROJECT_DIR/WhisperClip.xcodeproj"

export WHISPERCLIP_VERSION="$(cat version)"
export WHISPERCLIP_CODE_SIGN_IDENTITY="${WHISPERCLIP_CODE_SIGN_IDENTITY:--}"
export WHISPERCLIP_TEAM_ID="${WHISPERCLIP_TEAM_ID:-}"

xcodegen generate --spec project.yml --project "$PROJECT_DIR"

# Reuse the package's lockfile so Xcode resolves the same transitive dependency versions as SwiftPM.
SWIFTPM_DIR="$PROJECT/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$SWIFTPM_DIR"
cp Package.resolved "$SWIFTPM_DIR/Package.resolved"

echo "Generated $PROJECT"

if [[ "${1:-}" == "--open" ]]; then
  open "$PROJECT"
fi
