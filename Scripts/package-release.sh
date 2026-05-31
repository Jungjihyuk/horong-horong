#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_PATH="${APP_PATH:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SCHEME="${SCHEME:-HorongHorong}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_ROOT/build/DerivedData}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$PROJECT_ROOT/HorongHorong/HorongHorong.entitlements}"
SKIP_SIGN=0
SKIP_BUILD=0
SKIP_MAIN_CHECK=0

usage() {
  cat <<'EOF'
Usage:
  Scripts/package-release.sh [--app <path>] [--version <version>] [--output <dir>] [--skip-build] [--skip-main-check] [--skip-sign]

Defaults:
  --app      build Release/호롱호롱.app from the current main branch checkout
  --version  MARKETING_VERSION from project.yml
  --output   project root
  signing    ad-hoc sign with HorongHorong.entitlements before packaging

Environment overrides:
  APP_PATH=/path/to/호롱호롱.app VERSION=0.1.2 OUTPUT_DIR=dist Scripts/package-release.sh
  SCHEME=HorongHorong CONFIGURATION=Release DERIVED_DATA_PATH=build/DerivedData Scripts/package-release.sh
  SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" Scripts/package-release.sh
EOF
}

project_value() {
  local key="$1"
  awk -F'"' -v key="$key" '$0 ~ key ":" { print $2; exit }' "$PROJECT_ROOT/project.yml"
}

require_main_checkout() {
  local branch
  branch="$(git -C "$PROJECT_ROOT" branch --show-current)"
  if [[ "$branch" != "main" ]]; then
    echo "Release packaging must run from main. Current branch: $branch" >&2
    echo "Pass --skip-main-check only for a deliberate local test build." >&2
    exit 1
  fi

  git -C "$PROJECT_ROOT" fetch origin main
  local local_head remote_head
  local_head="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
  remote_head="$(git -C "$PROJECT_ROOT" rev-parse origin/main)"
  if [[ "$local_head" != "$remote_head" ]]; then
    echo "Local main is not up to date with origin/main." >&2
    echo "Pull or merge the latest main before packaging a release." >&2
    exit 1
  fi
}

require_clean_tree() {
  if [[ -n "$(git -C "$PROJECT_ROOT" status --short)" ]]; then
    echo "Working tree has uncommitted changes. Commit or stash them before packaging." >&2
    git -C "$PROJECT_ROOT" status --short >&2
    exit 1
  fi
}

generate_project() {
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --spec "$PROJECT_ROOT/project.yml"
  else
    echo "xcodegen is required to sync project.yml into the Xcode project." >&2
    exit 1
  fi
}

build_release_app() {
  xcodebuild \
    -project "$PROJECT_ROOT/HorongHorong.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

  APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/호롱호롱.app"
}

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist"
}

validate_app_version() {
  local plist="$APP_PATH/Contents/Info.plist"
  local app_version app_build
  app_version="$(plist_value "$plist" "CFBundleShortVersionString")"
  app_build="$(plist_value "$plist" "CFBundleVersion")"

  if [[ "$app_version" != "$VERSION" ]]; then
    echo "Built app version mismatch: expected $VERSION, got $app_version" >&2
    exit 1
  fi

  if [[ -n "$BUILD_NUMBER" && "$app_build" != "$BUILD_NUMBER" ]]; then
    echo "Built app build mismatch: expected $BUILD_NUMBER, got $app_build" >&2
    exit 1
  fi
}

sign_app() {
  if [[ "$SKIP_SIGN" -eq 1 ]]; then
    echo "Skipping app signing"
    return
  fi

  if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
    echo "Entitlements file not found: $ENTITLEMENTS_PATH" >&2
    exit 1
  fi

  local executable_name executable_path signed_executable
  executable_name="$(plist_value "$APP_PATH/Contents/Info.plist" "CFBundleExecutable")"
  executable_path="$APP_PATH/Contents/MacOS/$executable_name"
  signed_executable="$(mktemp "${TMPDIR:-/tmp}/horonghorong-main.XXXXXX")"

  echo "Signing app with identity: $SIGN_IDENTITY"
  cp "$executable_path" "$signed_executable"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$signed_executable"
  cp "$signed_executable" "$executable_path"
  rm -f "$signed_executable"

  codesign \
    --force \
    --sign "$SIGN_IDENTITY" \
    --timestamp=none \
    --entitlements "$ENTITLEMENTS_PATH" \
    "$APP_PATH"

  if ! codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.personal-information.calendars"; then
    echo "Signed app is missing reminders/calendar entitlement." >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --skip-main-check)
      SKIP_MAIN_CHECK=1
      shift
      ;;
    --skip-sign)
      SKIP_SIGN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION="$(project_value "MARKETING_VERSION")"
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(project_value "CURRENT_PROJECT_VERSION")"
fi

if [[ -z "$VERSION" ]]; then
  echo "Could not resolve version. Pass --version 0.1.2." >&2
  exit 1
fi

if [[ -z "$APP_PATH" ]]; then
  if [[ "$SKIP_MAIN_CHECK" -eq 0 ]]; then
    require_main_checkout
  fi
  generate_project
  require_clean_tree
  if [[ "$SKIP_BUILD" -eq 0 ]]; then
    build_release_app
  else
    APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/호롱호롱.app"
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  echo "Build Release first or pass --app <path>." >&2
  exit 1
fi

validate_app_version
sign_app

mkdir -p "$OUTPUT_DIR"

ZIP_PATH="$OUTPUT_DIR/HorongHorong-$VERSION.zip"
DMG_PATH="$OUTPUT_DIR/HorongHorong-$VERSION.dmg"
DMG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/horonghorong-dmg-root.XXXXXX")"

cleanup() {
  rm -rf "$DMG_ROOT"
}
trap cleanup EXIT

echo "Packaging HorongHorong $VERSION ($BUILD_NUMBER)"
echo "App: $APP_PATH"
echo "Output: $OUTPUT_DIR"

rm -f "$ZIP_PATH" "$DMG_PATH"

echo "Creating zip: $ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Preparing dmg root"
ditto "$APP_PATH" "$DMG_ROOT/호롱호롱.app"
ln -s /Applications "$DMG_ROOT/Applications"

echo "Creating dmg: $DMG_PATH"
hdiutil create \
  -volname "HorongHorong $VERSION" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Done"
ls -lh "$ZIP_PATH" "$DMG_PATH"
