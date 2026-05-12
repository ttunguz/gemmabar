#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="${CONFIGURATION:-release}"
TRIPLE_DIR=".build/arm64-apple-macosx/$CONFIGURATION"
OUTPUT_DIR="${OUTPUT_DIR:-.build/GemmaBar-bundled}"
APP_PATH="$OUTPUT_DIR/GemmaBar.app"
RESOURCES_DIR="$APP_PATH/Contents/Resources"
MACOS_DIR="$APP_PATH/Contents/MacOS"

BUNDLE_MODELS="${BUNDLE_MODELS:-0}"
BUNDLE_PARAKEET="${BUNDLE_PARAKEET:-0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-${GEMMABAR_SIGN_IDENTITY:--}}"
ENTITLEMENTS="${ENTITLEMENTS:-Sources/GemmaBar/GemmaBar.entitlements}"
VERIFY_GATEKEEPER="${VERIFY_GATEKEEPER:-0}"

DICTATION_MODEL="${DICTATION_MODEL:-$HOME/Documents/coding/MLX/models/gemma-4-e4b-it-4bit}"
PARAKEET_VENV="${PARAKEET_VENV:-$HOME/Documents/coding/parakeet/.venv}"
PARAKEET_CACHE="${PARAKEET_CACHE:-$HOME/.cache/huggingface/hub/models--mlx-community--parakeet-tdt-0.6b-v2}"

echo "==> Building GemmaBar and SwiftLM ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product GemmaBar
swift build -c "$CONFIGURATION" --product SwiftLM

echo "==> Assembling $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/SwiftLM"

cp "$TRIPLE_DIR/GemmaBar" "$MACOS_DIR/GemmaBar"
cp "Sources/GemmaBar/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$TRIPLE_DIR/SwiftLM" "$RESOURCES_DIR/SwiftLM/SwiftLM"

if [[ -f "$TRIPLE_DIR/mlx.metallib" ]]; then
  cp "$TRIPLE_DIR/mlx.metallib" "$RESOURCES_DIR/SwiftLM/mlx.metallib"
  cp "$TRIPLE_DIR/mlx.metallib" "$RESOURCES_DIR/SwiftLM/default.metallib"
elif [[ -f "$TRIPLE_DIR/default.metallib" ]]; then
  cp "$TRIPLE_DIR/default.metallib" "$RESOURCES_DIR/SwiftLM/default.metallib"
  cp "$TRIPLE_DIR/default.metallib" "$RESOURCES_DIR/SwiftLM/mlx.metallib"
elif [[ -f "$HOME/.local/bin/mlx.metallib" ]]; then
  cp "$HOME/.local/bin/mlx.metallib" "$RESOURCES_DIR/SwiftLM/mlx.metallib"
  cp "$HOME/.local/bin/mlx.metallib" "$RESOURCES_DIR/SwiftLM/default.metallib"
else
  echo "error: no mlx.metallib/default.metallib found" >&2
  exit 1
fi

if [[ "$BUNDLE_MODELS" == "1" ]]; then
  echo "==> Bundling dictation model"
  mkdir -p "$RESOURCES_DIR/Models"
  if [[ -d "$DICTATION_MODEL" ]]; then
    ditto "$DICTATION_MODEL" "$RESOURCES_DIR/Models/gemma-4-e4b-it-4bit"
  else
    echo "warning: dictation model not found: $DICTATION_MODEL" >&2
  fi
fi

if [[ "$BUNDLE_PARAKEET" == "1" ]]; then
  echo "==> Bundling Parakeet runtime"
  mkdir -p "$RESOURCES_DIR/Parakeet"
  if [[ -d "$PARAKEET_VENV" ]]; then
    ditto "$PARAKEET_VENV" "$RESOURCES_DIR/Parakeet/.venv"
  else
    echo "warning: Parakeet venv not found: $PARAKEET_VENV" >&2
  fi
  if [[ -d "$PARAKEET_CACHE" ]]; then
    mkdir -p "$RESOURCES_DIR/Parakeet/hf-cache"
    ditto "$PARAKEET_CACHE" "$RESOURCES_DIR/Parakeet/hf-cache/$(basename "$PARAKEET_CACHE")"
  else
    echo "warning: Parakeet cache not found: $PARAKEET_CACHE" >&2
  fi
fi

chmod +x "$MACOS_DIR/GemmaBar" "$RESOURCES_DIR/SwiftLM/SwiftLM"

codesign_common_args=(--force --strict --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
  codesign_common_args+=(--timestamp)
else
  codesign_common_args+=(--timestamp=none)
fi

echo "==> Signing with identity: $SIGN_IDENTITY"
while IFS= read -r -d '' metallib; do
  codesign "${codesign_common_args[@]}" "$metallib"
done < <(find "$APP_PATH/Contents" -type f -name '*.metallib' -print0)
codesign "${codesign_common_args[@]}" "$RESOURCES_DIR/SwiftLM/SwiftLM"
codesign "${codesign_common_args[@]}" --entitlements "$ENTITLEMENTS" "$MACOS_DIR/GemmaBar"
codesign "${codesign_common_args[@]}" --entitlements "$ENTITLEMENTS" "$APP_PATH"

codesign --verify --strict --verbose=4 "$APP_PATH"
if [[ "$VERIFY_GATEKEEPER" == "1" ]]; then
  spctl --assess --type execute --verbose=4 "$APP_PATH"
fi

echo "==> Bundle complete"
echo "App: $APP_PATH"
du -sh "$APP_PATH"
