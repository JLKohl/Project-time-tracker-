#!/bin/bash
# Builds "Project Time Tracker.app" into the build folder.
# With --install it also copies the app into your Applications folder and opens it.
#
#   ./scripts/build-app.sh             build only
#   ./scripts/build-app.sh --install   build, install and open
set -euo pipefail

APP_NAME="Project Time Tracker"
EXECUTABLE="ProjectTimeTracker"

cd "$(dirname "$0")/.."

INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        *) echo "Unknown option: $arg" >&2; echo "Usage: $0 [--install]" >&2; exit 1 ;;
    esac
done

echo "Building $APP_NAME (the first time takes a minute or two)…"
swift build -c release --product "$EXECUTABLE"
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Sign it for this Mac only ("ad hoc") so macOS will run it and allow Open at Login.
codesign --force --sign - "$APP"

echo "Built: $PWD/$APP"

if [ "$INSTALL" = true ]; then
    DEST="/Applications"
    if [ ! -w "$DEST" ]; then
        DEST="$HOME/Applications"
        mkdir -p "$DEST"
    fi

    # Quit any copy that's running (including one started with `swift run`) so it can be replaced.
    if pkill -x "$EXECUTABLE" 2>/dev/null; then
        sleep 1
    fi

    rm -rf "$DEST/$APP_NAME.app"
    cp -R "$APP" "$DEST/"
    echo "Installed: $DEST/$APP_NAME.app"
    open "$DEST/$APP_NAME.app"
    echo "Look for the timer icon in your menu bar."
fi
