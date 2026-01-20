#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

SRC_DIR="$ROOT_DIR/src"
BUILD_DIR="$ROOT_DIR/build"

# ---- Find swiftc (prefer swiftly) ----
export PATH="$HOME/.swiftly/bin:$PATH"

pick_swiftc() {
  if [[ -x "$HOME/.swiftly/bin/swiftc" ]]; then
    echo "$HOME/.swiftly/bin/swiftc"
    return 0
  fi
  command -v swiftc >/dev/null 2>&1 && command -v swiftc && return 0
  return 1
}

SWIFTC_PATH="$(pick_swiftc)" || {
  echo "[Error] swiftc not found (install swiftly snapshot toolchain first)."
  exit 1
}

# ---- sourcekit-lsp ----
TOOLCHAIN_BIN="$(cd "$(dirname "$SWIFTC_PATH")" && pwd)"
SOURCEKIT_LSP_PATH="$TOOLCHAIN_BIN/sourcekit-lsp"

if [[ ! -x "$SOURCEKIT_LSP_PATH" ]]; then
  if command -v sourcekit-lsp >/dev/null 2>&1; then
    SOURCEKIT_LSP_PATH="$(command -v sourcekit-lsp)"
  else
    echo "[Error] sourcekit-lsp not found."
    exit 1
  fi
fi

# ---- Embedded Swift target ----
SWIFT_TARGET="armv7-none-none-eabi"

SWIFT_RESOURCE_DIR="$("$SWIFTC_PATH" -print-target-info -target "$SWIFT_TARGET" \
  | awk -F'"' '/runtimeResourcePath/ {print $4; exit}')"

[[ -d "$SWIFT_RESOURCE_DIR/embedded" ]] || {
  echo "[Error] Embedded Swift stdlib not found."
  exit 1
}

mkdir -p "$BUILD_DIR" "$ROOT_DIR/.vscode" "$ROOT_DIR/.sourcekit-lsp"

# ============================================================
# Swift source discovery (bash 3.2 compatible)
# Rules:
#   1) MMIO.swift
#   2) Clock.swift
#   3) Timer.swift
#   4) main.swift
#   5) rest sorted
# ============================================================

SWIFT_SRCS=""

add_if_exists() {
  [[ -f "$1" ]] && SWIFT_SRCS="$SWIFT_SRCS $1"
}

add_if_exists "$SRC_DIR/MMIO.swift"
add_if_exists "$SRC_DIR/Clock.swift"
add_if_exists "$SRC_DIR/Timer.swift"
add_if_exists "$SRC_DIR/main.swift"

# Add remaining .swift files
find "$SRC_DIR" -maxdepth 1 -type f -name '*.swift' | sort | while read -r f; do
  case "$(basename "$f")" in
    MMIO.swift|Clock.swift|Timer.swift|main.swift) ;;
    *) SWIFT_SRCS="$SWIFT_SRCS $f" ;;
  esac
done

# shellcheck disable=SC2086
SWIFT_SRCS=$(echo $SWIFT_SRCS)

if [[ -z "$SWIFT_SRCS" ]]; then
  echo "[Error] No Swift files found in src/"
  exit 1
fi

CPU="cortex-m3"

# ---- compile_commands.json (FOR VS CODE ONLY) ----
BASE_CMD="$SWIFTC_PATH -typecheck -target $SWIFT_TARGET \
-Xfrontend -enable-experimental-feature -Xfrontend Embedded \
-Xfrontend -target-cpu -Xfrontend $CPU \
-Xcc -mcpu=$CPU -Xcc -mthumb -Xcc -fno-short-enums \
-resource-dir $SWIFT_RESOURCE_DIR -I $SWIFT_RESOURCE_DIR/embedded \
$SWIFT_SRCS"

OUT_DB="$BUILD_DIR/compile_commands.json"

echo "[" >"$OUT_DB"
FIRST=1
for f in $SWIFT_SRCS; do
  REL="src/$(basename "$f")"
  [[ $FIRST -eq 1 ]] || echo "," >>"$OUT_DB"
  FIRST=0
  cat >>"$OUT_DB" <<EOF
  {
    "directory": "$ROOT_DIR",
    "file": "$REL",
    "command": "$BASE_CMD"
  }
EOF
done
echo "]" >>"$OUT_DB"

# Root-level link (VS Code requirement)
ln -sf "build/compile_commands.json" "$ROOT_DIR/compile_commands.json"

# ---- SourceKit-LSP config ----
cat >"$ROOT_DIR/.sourcekit-lsp/config.json" <<EOF
{
  "compilationDatabase": {
    "searchPaths": ["$ROOT_DIR", "$ROOT_DIR/build"]
  }
}
EOF

# ---- VS Code settings ----
cat >"$ROOT_DIR/.vscode/settings.json" <<EOF
{
  "swift.path.swift_driver_bin": "$TOOLCHAIN_BIN",
  "swift.path.sourcekit-lsp": "$SOURCEKIT_LSP_PATH"
}
EOF

cat >"$ROOT_DIR/.vscode/extensions.json" <<'EOF'
{
  "recommendations": ["swiftlang.swift-vscode"]
}
EOF

echo "[Success] VS Code environment generated."
echo
echo "Swift files detected (order used):"
for f in $SWIFT_SRCS; do
  echo "  - src/$(basename "$f")"
done
echo
echo "NOW DO THIS:"
echo "  1) VS Code → Developer: Reload Window"
echo "  2) VS Code → Swift: Restart Language Server"