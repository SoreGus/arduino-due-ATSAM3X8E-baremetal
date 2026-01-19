#!/usr/bin/env bash
set -euo pipefail

BAUD="${1:-115200}"

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

need_one() {
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

pick_port_macos() {
  # Prefer Arduino Due as /dev/cu.usbmodem*
  local p
  p="$(ls /dev/cu.usbmodem* 2>/dev/null | head -n 1 || true)"
  [[ -n "$p" ]] && { echo "$p"; return 0; }
  p="$(ls /dev/cu.usbserial* 2>/dev/null | head -n 1 || true)"
  [[ -n "$p" ]] && { echo "$p"; return 0; }
  return 1
}

pick_port_linux() {
  local p
  p="$(ls /dev/ttyACM* 2>/dev/null | head -n 1 || true)"
  [[ -n "$p" ]] && { echo "$p"; return 0; }
  p="$(ls /dev/ttyUSB* 2>/dev/null | head -n 1 || true)"
  [[ -n "$p" ]] && { echo "$p"; return 0; }
  return 1
}

install_hint() {
  echo "[Error] No supported serial tool found (picocom or screen)."
  if is_macos; then
    echo "[Info] Install picocom with Homebrew:"
    echo "       brew install picocom"
    echo "[Info] Or use screen (usually already available):"
    echo "       screen /dev/cu.usbmodemXXXX 115200"
  elif is_linux; then
    echo "[Info] Install picocom:"
    echo "       Debian/Ubuntu: sudo apt-get update && sudo apt-get install -y picocom"
    echo "       Fedora:        sudo dnf install -y picocom"
    echo "       Arch:          sudo pacman -S picocom"
    echo "[Info] Or use screen:"
    echo "       sudo apt-get install -y screen   (Debian/Ubuntu)"
  fi
}

main() {
  local port=""
  if is_macos; then
    port="$(pick_port_macos || true)"
  elif is_linux; then
    port="$(pick_port_linux || true)"
  else
    echo "[Error] Unsupported OS: $(uname -s)" >&2
    exit 1
  fi

  if [[ -z "$port" ]]; then
    echo "[Error] No serial port found. Plug the Due on the Programming Port (USB da esquerda)." >&2
    exit 1
  fi

  # Prefer picocom, fallback to screen
  local tool=""
  tool="$(need_one picocom screen || true)"
  if [[ -z "$tool" ]]; then
    install_hint
    exit 1
  fi

  echo "[Info] Port: $port"
  echo "[Info] Baud: $BAUD"

  if [[ "$tool" == "picocom" ]]; then
    echo "[Info] Using picocom. Exit: Ctrl+A then Ctrl+X"
    # --imap/crlf helps when device sends CRLF, and makes Enter behave
    exec picocom "$port" -b "$BAUD" --imap crcrlf --omap crlf
  else
    echo "[Info] Using screen. Exit: Ctrl+A then K (confirm)"
    exec screen "$port" "$BAUD"
  fi
}

main