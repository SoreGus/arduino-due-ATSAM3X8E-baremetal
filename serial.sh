#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./serial.sh                         -> auto-detect; if multiple, menu
#   ./serial.sh 115200                  -> choose baud; auto-detect; if multiple, menu
#   ./serial.sh 115200 /dev/cu.usbmodem14201 -> explicit baud + port
#
# Exit picocom: Ctrl+A then Ctrl+X
# Exit screen:  Ctrl+A then K (confirm)

BAUD="${1:-115200}"
PORT_ARG="${2:-}"

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

install_hint() {
  echo "[Error] No supported serial tool found (picocom or screen)." >/dev/tty
  if is_macos; then
    echo "[Info] Install picocom with Homebrew: brew install picocom" >/dev/tty
    echo "[Info] Or use screen: screen /dev/cu.usbmodemXXXX 115200" >/dev/tty
  else
    echo "[Info] Install picocom: sudo apt-get install -y picocom" >/dev/tty
    echo "[Info] Or use screen:  sudo apt-get install -y screen" >/dev/tty
  fi
}

list_ports_macos() {
  ls /dev/cu.usbmodem* /dev/cu.usbserial* 2>/dev/null || true
}

list_ports_linux() {
  ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || true
}

# Bash 3.2 friendly: build array using a temp file (no mapfile)
PORTS=()

build_ports_array() {
  PORTS=()
  local tmp
  tmp="$(mktemp -t serial_ports)"

  # Collect + sort
  if is_macos; then
    list_ports_macos | sed '/^$/d' | sort -u > "$tmp"
  elif is_linux; then
    list_ports_linux | sed '/^$/d' | sort -u > "$tmp"
  else
    echo "[Error] Unsupported OS: $(uname -s)" >/dev/tty
    rm -f "$tmp"
    exit 1
  fi

  # Read into array
  local line=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    PORTS+=( "$line" )
  done < "$tmp"

  rm -f "$tmp"
}

choose_port_menu() {
  local n="${#PORTS[@]}"
  if (( n == 0 )); then
    echo "[Error] No serial port found. Plug the Due no Programming Port." >/dev/tty
    exit 1
  fi

  if (( n == 1 )); then
    echo "${PORTS[0]}"
    return 0
  fi

  # Ensure terminal is sane (fixes “no prompt/no echo” after Ctrl+C in picocom)
  stty sane < /dev/tty >/dev/tty 2>/dev/null || true

  echo "[Info] Multiple serial ports found:" >/dev/tty
  local i=0
  while (( i < n )); do
    echo "  [$((i+1))] ${PORTS[$i]}" >/dev/tty
    i=$((i+1))
  done

  local ans=""
  while true; do
    printf "[Info] Choose port (1-%s): " "$n" >/dev/tty
    read -r ans < /dev/tty || true
    [[ -z "$ans" ]] && { echo "[Error] Enter a number." >/dev/tty; continue; }

    case "$ans" in
      *[!0-9]*)
        echo "[Error] Enter a number." >/dev/tty
        continue
        ;;
    esac

    if (( ans < 1 || ans > n )); then
      echo "[Error] Out of range." >/dev/tty
      continue
    fi

    echo "${PORTS[$((ans-1))]}"
    return 0
  done
}

pick_port() {
  if [[ -n "$PORT_ARG" ]]; then
    if [[ ! -e "$PORT_ARG" ]]; then
      echo "[Error] Provided port does not exist: $PORT_ARG" >/dev/tty
      exit 1
    fi
    echo "$PORT_ARG"
    return 0
  fi

  build_ports_array
  choose_port_menu
}

main() {
  local port
  port="$(pick_port)"

  local tool=""
  tool="$(need_one picocom screen || true)"
  if [[ -z "$tool" ]]; then
    install_hint
    exit 1
  fi

  echo "[Info] Port: $port" >/dev/tty
  echo "[Info] Baud: $BAUD" >/dev/tty

  if [[ "$tool" == "picocom" ]]; then
    echo "[Info] Using picocom. Exit: Ctrl+A then Ctrl+X" >/dev/tty
    exec picocom "$port" -b "$BAUD" --imap crcrlf --omap crlf
  else
    echo "[Info] Using screen. Exit: Ctrl+A then K (confirm)" >/dev/tty
    exec screen "$port" "$BAUD"
  fi
}

main