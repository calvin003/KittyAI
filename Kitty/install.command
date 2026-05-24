#!/usr/bin/env bash
# Kitty installer
# ----------------
# Uninstalls any existing Kitty.app on this Mac, then builds and launches
# the cat-mascot version from this project. Safe to re-run.
#
# Double-click this file in Finder, or run: bash install.command

set -uo pipefail
LOG="/tmp/kitty-install.log"
exec > >(tee "$LOG") 2>&1

cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"

echo "==[ Kitty installer ]======================================"
echo "Project : $PROJECT_DIR"
echo "Log     : $LOG"
echo "Date    : $(date)"
echo "============================================================"
echo

# --- 1. quit + remove any existing Kitty ---------------------------------
echo "==> [1/8] quitting + removing any existing Kitty..."
osascript -e 'tell application "Kitty" to quit' 2>/dev/null || true
pkill -i -x Kitty 2>/dev/null || true
sleep 0.5
for p in \
  "/Applications/Kitty.app" \
  "$HOME/Applications/Kitty.app" \
  "$HOME/Library/Application Support/Kitty" \
  "$HOME/Library/Caches/com.heykitty.Kitty" \
  "$HOME/Library/Caches/Kitty" \
  "$HOME/Library/Preferences/com.heykitty.Kitty.plist" \
  "$HOME/Library/Logs/Kitty" \
  "$HOME/Library/Saved Application State/com.heykitty.Kitty.savedState"; do
  if [ -e "$p" ]; then
    echo "    rm $p"
    rm -rf "$p" 2>/dev/null || true
  fi
done

# --- 2. toolchain checks --------------------------------------------------
echo
echo "==> [2/8] checking toolchain..."
if ! command -v brew >/dev/null 2>&1; then
  echo "[FAIL] Homebrew is not installed."
  echo "       Install it first: https://brew.sh"
  echo "       Then re-run this script."
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "[FAIL] Xcode command line tools missing. Run:  xcode-select --install"
  exit 1
fi
echo "    brew    : $(command -v brew)"
echo "    xcode   : $(xcode-select -p)"

# --- 3. brew installs (xcodegen + ollama) ---------------------------------
echo
echo "==> [3/8] ensuring xcodegen + ollama via brew..."
for tool in xcodegen ollama; do
  if brew list "$tool" >/dev/null 2>&1; then
    echo "    $tool already installed"
  else
    echo "    brew install $tool"
    brew install "$tool"
  fi
done

# --- 4. start ollama daemon -----------------------------------------------
echo
echo "==> [4/8] starting ollama (if not already running)..."
if curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
  echo "    ollama already serving on :11434"
else
  ( nohup ollama serve >/tmp/kitty-ollama.log 2>&1 & ) >/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    if curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
      echo "    ollama up after ${i}s"
      break
    fi
  done
fi

# --- 5. pull the model ----------------------------------------------------
MODEL="${CLICKY_MODEL:-llama3.2}"
echo
echo "==> [5/8] ensuring model '$MODEL' is pulled..."
if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -q "^$MODEL"; then
  echo "    $MODEL already present"
else
  echo "    pulling $MODEL (~2GB, takes a few minutes the first time)..."
  ollama pull "$MODEL"
fi

# --- 6. xcodegen ----------------------------------------------------------
echo
echo "==> [6/8] generating Kitty.xcodeproj..."
xcodegen generate

# --- 7. build -------------------------------------------------------------
echo
echo "==> [7/8] building Kitty.app (Release)..."
# iCloud Drive (which is what ~/Documents usually is) stamps files with
# extended attributes that codesign refuses to sign. Strip them from sources
# AND build outside iCloud entirely so they don't come back mid-build.
xattr -cr "$PROJECT_DIR" 2>/dev/null || true
BUILD_DIR="/tmp/kitty-build"
rm -rf "$BUILD_DIR"

set -e
xcodebuild \
  -project Kitty.xcodeproj \
  -scheme Kitty \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  -quiet \
  build
set +e

BUILT_APP="$(/usr/bin/find "$BUILD_DIR/Build/Products/Release" -maxdepth 2 -name 'Kitty.app' -type d 2>/dev/null | head -1)"
if [ -z "$BUILT_APP" ] || [ ! -d "$BUILT_APP" ]; then
  echo "[FAIL] Build did not produce Kitty.app."
  echo "       Full log at: $LOG"
  exit 1
fi
echo "    built: $BUILT_APP"

# --- 8. install + launch --------------------------------------------------
DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/Kitty.app"
cp -R "$BUILT_APP" "$DEST/Kitty.app"
# Strip quarantine + any other xattrs Gatekeeper / iCloud might add.
xattr -cr "$DEST/Kitty.app" 2>/dev/null || true

echo
echo "==> [8/8] launching $DEST/Kitty.app ..."
open "$DEST/Kitty.app"

echo
echo "============================================================"
echo "[DONE] Kitty is installed at $DEST/Kitty.app and launching."
echo ""
echo "First-launch permission prompts (say YES to all three):"
echo "  1. Microphone"
echo "  2. Speech Recognition"
echo "  3. Accessibility — System Settings will open; toggle Kitty on."
echo ""
echo "Then hold  ⌃⌥  (Ctrl+Option)  anywhere and talk to the cat."
echo "============================================================"
