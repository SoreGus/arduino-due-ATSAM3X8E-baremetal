#!/usr/bin/env bash
set -euo pipefail

# Always run from project root (folder where this script is)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

SRC_DIR="$ROOT_DIR/src"
ARM_DIR="$ROOT_DIR/arm"
BUILD_DIR="$ROOT_DIR/build"
mkdir -p "$BUILD_DIR"

LOG="$BUILD_DIR/last_run.log"
: > "$LOG"

MODE="${1:-run}"

TMP_PORTS_BEFORE="$(mktemp -t due_ports_before)"
TMP_PORTS_AFTER="$(mktemp -t due_ports_after)"
TMP_UPLOAD="$(mktemp -t due_upload)"
trap 'rm -f "$TMP_PORTS_BEFORE" "$TMP_PORTS_AFTER" "$TMP_UPLOAD"' EXIT

# ---------- Pretty output ----------
BOLD=$'\033[1m'
RED=$'\033[31m'
YEL=$'\033[33m'
GRN=$'\033[32m'
CYN=$'\033[36m'
RST=$'\033[0m'

log()   { echo "${BOLD}${CYN}[Info]${RST} ${BOLD}$*${RST}" | tee -a "$LOG"; }
ok()    { echo "${BOLD}${GRN}[Success]${RST} ${BOLD}$*${RST}" | tee -a "$LOG"; }
warn()  { echo "${BOLD}${YEL}[Warning]${RST} ${BOLD}$*${RST}" | tee -a "$LOG"; }
err()   { echo "${BOLD}${RED}[Error]${RST} ${BOLD}$*${RST}" | tee -a "$LOG"; }

run_cmd() {
  log "Running: $*"
  set +e
  "$@" 2>&1 | tee -a "$LOG"
  rc=${PIPESTATUS[0]}
  set -e
  return $rc
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  ok "Found: $1 -> $(command -v "$1")"
}

# ---------- Install hints ----------
install_hints_toolchain() {
  uname_s="$(uname -s)"
  case "$uname_s" in
    Darwin)
      cat <<'EOF'
Install ARM GNU toolchain:
  brew install make
  brew install --cask gcc-arm-embedded
EOF
      ;;
    Linux)
      cat <<'EOF'
Install ARM GNU toolchain (Debian/Ubuntu):
  sudo apt update
  sudo apt install -y build-essential gcc-arm-none-eabi binutils-arm-none-eabi
EOF
      ;;
    *)
      cat <<'EOF'
Install:
  - make
  - arm-none-eabi-gcc
  - arm-none-eabi-objcopy
Using your OS package manager.
EOF
      ;;
  esac
}

install_hints_bossac() {
  uname_s="$(uname -s)"
  case "$uname_s" in
    Darwin)
      cat <<'EOF'
Install bossac (Homebrew package name is bossa):
  brew install bossa
EOF
      ;;
    Linux)
      cat <<'EOF'
Install bossac (Debian/Ubuntu):
  sudo apt update
  sudo apt install -y bossac
EOF
      ;;
    *)
      cat <<'EOF'
Install bossac via your OS package manager or from source.
EOF
      ;;
  esac
}

install_hints_swiftly() {
  cat <<'EOF'
Install Embedded Swift toolchain (recommended via swiftly):

  brew install swiftly
  swiftly init
  swiftly install main-snapshot
  swiftly use main-snapshot
EOF
}

# ---------- Swiftly toolchain selection ----------
export PATH="$HOME/.swiftly/bin:$PATH"

pick_swiftc() {
  if [[ -x "$HOME/.swiftly/bin/swiftc" ]]; then
    echo "$HOME/.swiftly/bin/swiftc"
    return 0
  fi
  command -v swiftc || true
}

# ---------- SPM (indexing only) ----------
ensure_spm_package() {
  local pkg="$ROOT_DIR/Package.swift"
  if [[ -f "$pkg" ]]; then
    ok "SPM manifest exists: Package.swift"
    return 0
  fi

  log "Creating Package.swift for editor indexing (SourceKit)."
  cat > "$pkg" <<'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DueBareMetal",
    products: [],
    targets: [
        .target(
            name: "DueBareMetal",
            path: "src"
        )
    ]
)
EOF
  ok "Created: Package.swift"
}

# ---------- VS Code bootstrap ----------
ensure_vscode_workspace() {
  local ws="$ROOT_DIR/Due_BareMetal.code-workspace"
  local vsc_dir="$ROOT_DIR/.vscode"
  local settings="$vsc_dir/settings.json"
  local tasks="$vsc_dir/tasks.json"
  local open_cmd="$ROOT_DIR/Open_Due_BareMetal.command"

  mkdir -p "$vsc_dir"

  if [[ ! -f "$ws" ]]; then
    cat > "$ws" <<'EOF'
{
  "folders": [{ "path": "." }],
  "settings": {
    "swift.path": "${env:HOME}/.swiftly/bin/swift",
    "swift.sourcekit-lsp.path": "${env:HOME}/.swiftly/bin/sourcekit-lsp",
    "files.exclude": {
      "**/build": true
    }
  },
  "extensions": {
    "recommendations": ["sswg.swift-lang"]
  }
}
EOF
    ok "Created: Due_BareMetal.code-workspace"
  else
    ok "Workspace exists: Due_BareMetal.code-workspace"
  fi

  if [[ ! -f "$settings" ]]; then
    cat > "$settings" <<'EOF'
{
  "swift.path": "${env:HOME}/.swiftly/bin/swift",
  "swift.sourcekit-lsp.path": "${env:HOME}/.swiftly/bin/sourcekit-lsp"
}
EOF
    ok "Created: .vscode/settings.json"
  else
    ok "VS Code settings exists: .vscode/settings.json"
  fi

  if [[ ! -f "$tasks" ]]; then
    cat > "$tasks" <<'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build + Upload (run.sh)",
      "type": "shell",
      "command": "${workspaceFolder}/run.sh",
      "problemMatcher": [],
      "group": { "kind": "build", "isDefault": true }
    },
    {
      "label": "Setup (run.sh --setup)",
      "type": "shell",
      "command": "${workspaceFolder}/run.sh --setup",
      "problemMatcher": []
    }
  ]
}
EOF
    ok "Created: .vscode/tasks.json"
  else
    ok "VS Code tasks exists: .vscode/tasks.json"
  fi

  if [[ "$(uname -s)" == "Darwin" && ! -f "$open_cmd" ]]; then
    cat > "$open_cmd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"
export PATH="$HOME/.swiftly/bin:$PATH"

if command -v code >/dev/null 2>&1; then
  code "$ROOT_DIR/Due_BareMetal.code-workspace"
else
  open "$ROOT_DIR/Due_BareMetal.code-workspace"
fi
EOF
    chmod +x "$open_cmd"
    ok "Created: Open_Due_BareMetal.command (double click)"
  fi
}

# ---------- Ensure swiftly snapshot exists (best effort) ----------
ensure_swiftly_snapshot() {
  if [[ -x "$HOME/.swiftly/bin/swiftc" && -x "$HOME/.swiftly/bin/swift" ]]; then
    ok "swiftly toolchain already present in ~/.swiftly/bin"
    return 0
  fi

  if ! command -v swiftly >/dev/null 2>&1; then
    if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
      log "Installing swiftly via brew..."
      brew install swiftly
    else
      err "swiftly not found and auto-install is unavailable."
      install_hints_swiftly | tee -a "$LOG"
      return 1
    fi
  fi

  run_cmd swiftly init || true
  run_cmd swiftly install main-snapshot || true
  run_cmd swiftly use main-snapshot || true

  if [[ -x "$HOME/.swiftly/bin/swiftc" && -x "$HOME/.swiftly/bin/swift" ]]; then
    ok "swiftly snapshot ready: ~/.swiftly/bin/swiftc"
    return 0
  fi

  err "swiftly did not produce ~/.swiftly/bin/swiftc"
  return 1
}

# ---------- Setup mode ----------
if [[ "$MODE" == "--setup" ]]; then
  log "Setup mode: preparing SPM + VS Code + toolchain"

  mkdir -p "$BUILD_DIR"
  ensure_spm_package
  ensure_vscode_workspace

  if ! ensure_swiftly_snapshot; then
    warn "Toolchain setup incomplete. Build may fail until swiftly snapshot is installed."
  fi

  ok "Setup complete."
  log "Open the project with: Due_BareMetal.code-workspace"
  if [[ -f "$ROOT_DIR/Open_Due_BareMetal.command" ]]; then
    log "Or double click: Open_Due_BareMetal.command"
  fi
  exit 0
fi

# ---------- Port detection ----------
list_ports() {
  uname_s="$(uname -s)"
  if [[ "$uname_s" == "Darwin" ]]; then
    ls /dev/cu.usbmodem* /dev/cu.usbserial* 2>/dev/null || true
  else
    ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || true
  fi
}

pick_best_port() {
  ports="$(list_ports | tr '\r' '\n' | sed '/^$/d' || true)"
  [[ -n "$ports" ]] || { echo ""; return 0; }

  best="$(echo "$ports" | grep -E 'usbmodem|ttyACM' | head -n 1 || true)"
  [[ -z "$best" ]] && best="$(echo "$ports" | head -n 1 || true)"
  echo "$best"
}

# ---------- Bootloader trigger ----------
touch_1200bps() {
  local port="$1"
  log "Touch 1200bps on: $port (enter bootloader)"
  if command -v stty >/dev/null 2>&1; then
    stty -f "$port" 1200 2>/dev/null || stty -F "$port" 1200 2>/dev/null || true
  fi
  ( : > "$port" ) 2>/dev/null || true
}

wait_for_port_change_or_return() {
  local old="$1"
  local timeout_sec="${2:-10}"
  local end=$(( $(date +%s) + timeout_sec ))

  while [[ "$(date +%s)" -lt "$end" ]]; do
    local now
    now="$(pick_best_port)"
    if [[ -n "$now" && "$now" != "$old" ]]; then
      echo "$now"
      return 0
    fi
    if [[ -n "$old" && -e "$old" ]]; then
      echo "$old"
      return 0
    fi
    sleep 0.2
  done

  if [[ -n "$old" && -e "$old" ]]; then
    echo "$old"
    return 0
  fi

  echo ""
  return 0
}

# ---------- Main ----------
log "Project root: $ROOT_DIR"
log "Build dir: $BUILD_DIR"
log "Log file: $LOG (always overwritten each run)"

ensure_spm_package || true
ensure_vscode_workspace || true

need_cmd make || { err "make not found"; echo; install_hints_toolchain | tee -a "$LOG"; exit 1; }
need_cmd arm-none-eabi-gcc || { err "arm-none-eabi-gcc not found"; echo; install_hints_toolchain | tee -a "$LOG"; exit 1; }
need_cmd arm-none-eabi-objcopy || { err "arm-none-eabi-objcopy not found"; echo; install_hints_toolchain | tee -a "$LOG"; exit 1; }

SWIFTC_PATH="$(pick_swiftc)"
if [[ -z "${SWIFTC_PATH:-}" || ! -x "$SWIFTC_PATH" ]]; then
  err "swiftc not found."
  echo
  install_hints_swiftly | tee -a "$LOG"
  err "Run: ./run.sh --setup (it will try to install/activate swiftly snapshot automatically)"
  exit 1
fi

ok "Using swiftc -> $SWIFTC_PATH"
"$SWIFTC_PATH" --version 2>&1 | head -n 1 | tee -a "$LOG" >/dev/null || true

SWIFT_TARGET="armv7-none-none-eabi"

SWIFT_RESOURCE_DIR="$("$SWIFTC_PATH" -print-target-info -target "$SWIFT_TARGET" \
  | awk -F'"' '/runtimeResourcePath/ {print $4; exit}')"

if [[ -z "${SWIFT_RESOURCE_DIR:-}" || ! -d "$SWIFT_RESOURCE_DIR" ]]; then
  err "Could not determine Swift runtime resource dir via -print-target-info."
  exit 1
fi

if [[ ! -d "$SWIFT_RESOURCE_DIR/embedded" ]]; then
  err "Embedded Swift stdlib not found at: $SWIFT_RESOURCE_DIR/embedded"
  exit 1
fi

ok "Swift target: $SWIFT_TARGET"
ok "Swift resource dir: $SWIFT_RESOURCE_DIR"
ok "Swift embedded dir: $SWIFT_RESOURCE_DIR/embedded"

if ! command -v bossac >/dev/null 2>&1; then
  err "bossac not found."
  echo
  install_hints_bossac | tee -a "$LOG"
  exit 1
fi
ok "Found: bossac -> $(command -v bossac)"
run_cmd bossac --help || true

run_cmd make clean \
  BUILD_DIR="$BUILD_DIR" \
  SRC_DIR="$SRC_DIR" \
  ARM_DIR="$ARM_DIR" \
  || true

run_cmd make \
  SWIFTC="$SWIFTC_PATH" \
  SWIFT_RESOURCE_DIR="$SWIFT_RESOURCE_DIR" \
  SWIFT_TARGET="$SWIFT_TARGET" \
  BUILD_DIR="$BUILD_DIR" \
  SRC_DIR="$SRC_DIR" \
  ARM_DIR="$ARM_DIR" \
  || { err "Build failed"; exit 1; }

BIN="$BUILD_DIR/firmware.bin"
[[ -f "$BIN" ]] || { err "$BIN not generated (check Makefile)"; exit 1; }
ok "Build OK -> $BIN"

list_ports > "$TMP_PORTS_BEFORE" || true
log "Detected serial ports (before):"
if [[ -s "$TMP_PORTS_BEFORE" ]]; then
  sed 's/^/  /' "$TMP_PORTS_BEFORE" | tee -a "$LOG"
else
  warn "No candidate serial ports found."
  warn "Plug Arduino Due (Programming Port) and try again."
  exit 1
fi

PORT="$(pick_best_port)"
if [[ -z "$PORT" || ! -e "$PORT" ]]; then
  err "Could not pick a serial port automatically."
  warn "Make sure you are using the Programming Port (not Native USB)."
  exit 1
fi
ok "Using port: $PORT"

touch_1200bps "$PORT"
sleep 0.7

list_ports > "$TMP_PORTS_AFTER" || true
log "Detected serial ports (after touch):"
if [[ -s "$TMP_PORTS_AFTER" ]]; then
  sed 's/^/  /' "$TMP_PORTS_AFTER" | tee -a "$LOG"
else
  warn "No serial ports detected after touch (this can be normal briefly)."
fi

NEWPORT="$(wait_for_port_change_or_return "$PORT" 12)"
if [[ -z "$NEWPORT" || ! -e "$NEWPORT" ]]; then
  err "Port did not reappear for upload."
  warn "Try: press RESET on the Due (Programming Port) once, then run ./run.sh again."
  exit 1
fi
ok "Bootloader port: $NEWPORT"

log "Uploading $BIN via bossac..."
set +e
bossac -p "$NEWPORT" -e -w -v -b "$BIN" >"$TMP_UPLOAD" 2>&1
RC=$?
set -e

cat "$TMP_UPLOAD" | tee -a "$LOG"

if grep -qiE "Verify successful|Verify\s+OK|verify.*OK|CPU reset|boot from flash" "$TMP_UPLOAD"; then
  ok "Upload complete."
  exit 0
fi

if [[ $RC -eq 0 ]]; then
  ok "Upload complete (bossac exited cleanly)."
  exit 0
fi

err "Upload failed (rc=$RC). Check $LOG."
exit 1