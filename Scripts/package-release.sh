#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_PATH="${APP_PATH:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT}"
VERSION="${VERSION:-}"

usage() {
  cat <<'EOF'
Usage:
  Scripts/package-release.sh [--app <path>] [--version <version>] [--output <dir>]

Defaults:
  --app      newest Release/호롱호롱.app under ~/Library/Developer/Xcode/DerivedData/HorongHorong-*
  --version  MARKETING_VERSION from project.yml
  --output   project root

Environment overrides:
  APP_PATH=/path/to/호롱호롱.app VERSION=0.1.1 OUTPUT_DIR=dist Scripts/package-release.sh
EOF
}

find_release_app() {
  local derived_data_root="$HOME/Library/Developer/Xcode/DerivedData"
  local -a candidates=()

  while IFS= read -r -d '' app; do
    candidates+=("$app")
  done < <(find "$derived_data_root" \
    -path "*/HorongHorong-*/Build/Products/Release/호롱호롱.app" \
    -type d \
    -print0 2>/dev/null)

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${candidates[@]}" | while IFS= read -r app; do
    printf '%s\t%s\n' "$(stat -f '%m' "$app")" "$app"
  done | sort -rn | head -n 1 | cut -f2-
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
  VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$PROJECT_ROOT/project.yml")"
fi

if [[ -z "$VERSION" ]]; then
  echo "Could not resolve version. Pass --version 0.1.1." >&2
  exit 1
fi

if [[ -z "$APP_PATH" ]]; then
  if ! APP_PATH="$(find_release_app)"; then
    echo "Could not find Release app under ~/Library/Developer/Xcode/DerivedData." >&2
    echo "Build Release first or pass --app <path>." >&2
    exit 1
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  echo "Build Release first or pass --app <path>." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

ZIP_PATH="$OUTPUT_DIR/HorongHorong-$VERSION.zip"
DMG_PATH="$OUTPUT_DIR/HorongHorong-$VERSION.dmg"
DMG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/horonghorong-dmg-root.XXXXXX")"

cleanup() {
  rm -rf "$DMG_ROOT"
}
trap cleanup EXIT

echo "Packaging HorongHorong $VERSION"
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
