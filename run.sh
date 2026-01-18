#!/usr/bin/env bash
set -euo pipefail

# Arduino Due (SAM3X8E) — Bare metal upload via bootloader (Programming Port) + bossac
#
# What this script does:
# 1) Logs everything to last_run.log (overwritten each run)
# 2) Checks required build tools
# 3) Checks bossac (uploader) and gives install instructions if missing
# 4) Builds via make
# 5) Auto-detects the Programming Port (no parameter needed)
# 6) Tries the 1200bps "touch" reset to enter bootloader
# 7) Waits for USB re-enumeration and uploads firmware.bin via bossac
#
# Usage:
#   ./run.sh
#
# Notes:
# - Use the Programming Port (USB near the reset button), not the Native USB.
# - On Linux you may need: sudo usermod -a -G dialout $USER ; then log out/in.

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
Install ARM GNU Toolchain + make:
  brew install make arm-none-eabi-gcc
If brew says arm-none-eabi-gcc is unavailable, use:
  brew install --cask gcc-arm-embedded
Then ensure arm-none-eabi-gcc is in PATH.
EOF
      ;;
    Linux)
      cat <<'EOF'
Install ARM GNU Toolchain + make (Debian/Ubuntu):
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
Install bossac (uploader):
  brew install bossac
EOF
      ;;
    Linux)
      cat <<'EOF'
Install bossac (uploader):
  sudo apt update
  sudo apt install -y bossac
If your distro doesn't have bossac, install "arduino-cli" (without IDE) and use its bossac tool,
or build bossac from source.
EOF
      ;;
    *)
      cat <<'EOF'
Install bossac via your OS package manager or from source.
EOF
      ;;
  esac
}

# ---------- Port detection ----------
list_ports() {
  # Output one port per line, best-effort, cross-platform.
  # Prefer Programming Port style devices:
  # macOS: /dev/cu.usbmodem* (also sometimes /dev/cu.usbserial*)
  # Linux: /dev/ttyACM* (also sometimes /dev/ttyUSB*)
  uname_s="$(uname -s)"
  if [[ "$uname_s" == "Darwin" ]]; then
    ls /dev/cu.usbmodem* /dev/cu.usbserial* 2>/dev/null || true
  else
    ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || true
  fi
}

pick_best_port() {
  # Try to pick a stable candidate from current ports.
  # Priority:
  # 1) usbmodem / ttyACM
  # 2) usbserial / ttyUSB
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

  # macOS uses stty -f, Linux uses -F. Try both.
  if command -v stty >/dev/null 2>&1; then
    stty -f "$port" 1200 2>/dev/null || stty -F "$port" 1200 2>/dev/null || true
  fi

  # Quick open/close also helps on some hosts
  ( : > "$port" ) 2>/dev/null || true
}

wait_for_port_change_or_return() {
  # Wait for ports to change (new port appears) after 1200bps touch.
  # If it doesn't change, allow fallback to the same port if it still exists.
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
      # Sometimes it re-enumerates but keeps the same name; accept.
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
log "Log file: $LOG (always overwritten each run)"

need_cmd make || { err "make not found"; echo; install_hints_toolchain | tee -a "$LOG"; exit 1; }
need_cmd arm-none-eabi-gcc || { err "arm-none-eabi-gcc not found"; echo; install_hints_toolchain | tee -a "$LOG"; exit 1; }
need_cmd arm-none-eabi-objcopy || { err "arm-none-eabi-objcopy not found"; echo; install_hints_toolchain | tee -a "$LOG"; exit 1; }

if ! command -v bossac >/dev/null 2>&1; then
  err "bossac not found."
  echo
  install_hints_bossac | tee -a "$LOG"
  exit 1
fi
ok "Found: bossac -> $(command -v bossac)"
run_cmd bossac --help || true

# Build
run_cmd make clean || true
run_cmd make || { err "Build failed"; exit 1; }

BIN="firmware.bin"
[[ -f "$BIN" ]] || { err "$BIN not generated (check Makefile TARGET/BIN name)"; exit 1; }
ok "Build OK -> $BIN"

# Detect ports BEFORE touch (for debugging)
list_ports > "$TMP_PORTS_BEFORE" || true
log "Detected serial ports (before):"
if [[ -s "$TMP_PORTS_BEFORE" ]]; then
  cat "$TMP_PORTS_BEFORE" | sed 's/^/  /' | tee -a "$LOG"
else
  warn "No candidate serial ports found."
  warn "Plug Arduino Due (Programming Port) and try again."
  warn "On Linux, check permissions (dialout group) and cable."
  exit 1
fi

PORT="$(pick_best_port)"
if [[ -z "$PORT" || ! -e "$PORT" ]]; then
  err "Could not pick a serial port automatically."
  warn "Make sure you are using the Programming Port (not Native USB)."
  exit 1
fi
ok "Using port: $PORT"

# Trigger bootloader
touch_1200bps "$PORT"
sleep 0.7

# Detect ports AFTER touch
list_ports > "$TMP_PORTS_AFTER" || true
log "Detected serial ports (after touch):"
if [[ -s "$TMP_PORTS_AFTER" ]]; then
  cat "$TMP_PORTS_AFTER" | sed 's/^/  /' | tee -a "$LOG"
else
  warn "No serial ports detected after touch (this can be normal briefly)."
fi

NEWPORT="$(wait_for_port_change_or_return "$PORT" 12)"
if [[ -z "$NEWPORT" || ! -e "$NEWPORT" ]]; then
  err "Port did not reappear for upload."
  warn "Try: press RESET on the Due (Programming Port) once, then run ./run.sh again."
  warn "Also try a different USB cable/port."
  exit 1
fi
ok "Bootloader port: $NEWPORT"

# Upload
log "Uploading $BIN via bossac..."
set +e
bossac -p "$NEWPORT" -e -w -v -b "$BIN" >"$TMP_UPLOAD" 2>&1
RC=$?
set -e

cat "$TMP_UPLOAD" | tee -a "$LOG"

# Heuristic success checks (bossac output varies)
if grep -qiE "Verify successful|Verify\s+OK|verify.*OK|CPU reset|boot from flash" "$TMP_UPLOAD"; then
  ok "Upload complete."
  exit 0
fi

if [[ $RC -eq 0 ]]; then
  ok "Upload complete (bossac exited cleanly)."
  exit 0
fi

err "Upload failed (rc=$RC). Check $LOG."
warn "If it fails consistently, ensure you're using the Programming Port and the board is in bootloader mode."
exit 1