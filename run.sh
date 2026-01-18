#!/usr/bin/env bash
set -euo pipefail

LOG="last_run.log"
: > "$LOG"

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

# Loading spinner (no timer, no %). Logs command output only into last_run.log.
run_cmd_loading() {
  # Usage: run_cmd_loading "Description" cmd...
  local desc="$1"; shift

  # If stdout isn't a TTY (piped/CI), just run normally.
  if [[ ! -t 1 ]]; then
    run_cmd "$@"
    return $?
  fi

  local spin='|/-\'
  local i=0

  log "$desc"

  # Run command in background, log all output into LOG.
  set +e
  ("$@" >>"$LOG" 2>&1) &
  local pid=$!
  set -e

  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % 4 ))
    printf "\r${BOLD}${CYN}[Info]${RST} ${BOLD}%s... %c${RST}" "$desc" "${spin:$i:1}"
    sleep 0.12
  done

  wait "$pid"
  local rc=$?

  # Clear line
  printf "\r\033[2K"

  if [[ $rc -eq 0 ]]; then
    ok "$desc"
  else
    err "$desc (rc=$rc)"
  fi

  return $rc
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  ok "Found: $1 -> $(command -v "$1")"
}

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

install_hints_swiftly() {
  cat <<'EOF'
Install Embedded Swift toolchain (recommended via swiftly):

  brew install swiftly
  swiftly init
  swiftly install main-snapshot
  swiftly use main-snapshot

Then open a new shell (or run):
  exec zsh -l

Verify:
  which swiftc
  swiftc --version
EOF
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

install_hints_git() {
  uname_s="$(uname -s)"
  case "$uname_s" in
    Darwin)
      cat <<'EOF'
Install git:
  xcode-select --install
(or via Homebrew)
  brew install git
EOF
      ;;
    Linux)
      cat <<'EOF'
Install git (Debian/Ubuntu):
  sudo apt update
  sudo apt install -y git
EOF
      ;;
    *)
      cat <<'EOF'
Install git using your OS package manager.
EOF
      ;;
  esac
}

# Ensure CMSIS_5 is present in platform/CMSIS_5, clone if missing
ensure_cmsis5() {
  local cmsis_dir="platform/CMSIS_5"

  if [[ -d "$cmsis_dir" ]]; then
    ok "CMSIS_5 present -> $cmsis_dir"
    if [[ -d "$cmsis_dir/.git" ]]; then
      (
        cd "$cmsis_dir" 2>/dev/null || exit 0
        git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's/^/CMSIS_5 branch: /' | tee -a "$LOG" >/dev/null || true
        git rev-parse --short HEAD 2>/dev/null | sed 's/^/CMSIS_5 commit: /' | tee -a "$LOG" >/dev/null || true
      ) || true
    else
      warn "CMSIS_5 directory exists but is not a git repo: $cmsis_dir"
      warn "If you want auto-managed CMSIS_5, delete it and re-run ./run.sh"
    fi
    return 0
  fi

  log "CMSIS_5 not found. Bootstrapping into: $cmsis_dir"

  if ! command -v git >/dev/null 2>&1; then
    err "git not found (required to clone CMSIS_5)."
    echo
    install_hints_git | tee -a "$LOG"
    exit 1
  fi

  mkdir -p "platform"

  # Loading only (no %). Full git output goes to last_run.log.
  if ! run_cmd_loading "Cloning CMSIS_5" \
      git clone --progress "https://github.com/ARM-software/CMSIS_5.git" "$cmsis_dir"; then
    err "Failed to clone CMSIS_5"
    exit 1
  fi

  ok "Cloned CMSIS_5 -> $cmsis_dir"
}

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

# ---------- Swift toolchain selection ----------
export PATH="$HOME/.swiftly/bin:$PATH"

pick_swiftc() {
  if [[ -x "$HOME/.swiftly/bin/swiftc" ]]; then
    echo "$HOME/.swiftly/bin/swiftc"
    return 0
  fi
  command -v swiftc || true
}

# ---------- Main ----------
log "Log file: $LOG (always overwritten each run)"

# ---------- CMSIS_5 bootstrap (platform/CMSIS_5) ----------
ensure_cmsis5

need_cmd make || { err "make not found"; echo; install_hints_toolchain | tee -a "$LOG"; exit 1; }
need_cmd arm-none-eabi-gcc || { err "arm-none-eabi-gcc not found"; echo; install_hints_toolchain | tee -a "$LOG"; exit 1; }
need_cmd arm-none-eabi-objcopy || { err "arm-none-eabi-objcopy not found"; echo; install_hints_toolchain | tee -a "$LOG"; exit 1; }

SWIFTC_PATH="$(pick_swiftc)"
if [[ -z "${SWIFTC_PATH:-}" || ! -x "$SWIFTC_PATH" ]]; then
  err "swiftc not found."
  echo
  install_hints_swiftly | tee -a "$LOG"
  exit 1
fi

ok "Using swiftc -> $SWIFTC_PATH"
"$SWIFTC_PATH" --version 2>&1 | head -n 1 | tee -a "$LOG" >/dev/null || true

# IMPORTANT:
# This toolchain ships Swift.swiftmodule for armv7-none-none-eabi,
# but not for thumbv7m-none-none-eabi.
SWIFT_TARGET="armv7-none-none-eabi"

SWIFT_RESOURCE_DIR="$("$SWIFTC_PATH" -print-target-info -target "$SWIFT_TARGET" \
  | awk -F'"' '/runtimeResourcePath/ {print $4; exit}')"

if [[ -z "${SWIFT_RESOURCE_DIR:-}" || ! -d "$SWIFT_RESOURCE_DIR" ]]; then
  err "Could not determine Swift runtime resource dir via -print-target-info."
  err "Make sure you are using the swiftly snapshot toolchain."
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

run_cmd make clean || true
run_cmd make \
  SWIFTC="$SWIFTC_PATH" \
  SWIFT_RESOURCE_DIR="$SWIFT_RESOURCE_DIR" \
  SWIFT_TARGET="$SWIFT_TARGET" \
  || { err "Build failed"; exit 1; }

BIN="firmware.bin"
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