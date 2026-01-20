#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
ARDUINO_DIR="arduino"
REPO_URL="https://github.com/arduino/ArduinoCore-sam.git"
GITIGNORE=".gitignore"

# ---------- Helpers ----------
info()    { echo "[Info]    $*"; }
success() { echo "[Success] $*"; }
warn()    { echo "[Warning] $*"; }

# ---------- Create arduino dir ----------
if [[ ! -d "$ARDUINO_DIR" ]]; then
    info "Creating directory: $ARDUINO_DIR"
    mkdir -p "$ARDUINO_DIR"
else
    info "Directory already exists: $ARDUINO_DIR"
fi

# ---------- Clone repo ----------
if [[ ! -d "$ARDUINO_DIR/ArduinoCore-sam" ]]; then
    info "Cloning ArduinoCore-sam into $ARDUINO_DIR/"
    git clone "$REPO_URL" "$ARDUINO_DIR/ArduinoCore-sam"
    success "Repository cloned"
else
    warn "Repository already exists: $ARDUINO_DIR/ArduinoCore-sam"
fi

# ---------- Update .gitignore ----------
if [[ ! -f "$GITIGNORE" ]]; then
    info "Creating .gitignore"
    touch "$GITIGNORE"
fi

if grep -qx "$ARDUINO_DIR/" "$GITIGNORE"; then
    info "$ARDUINO_DIR/ already present in .gitignore"
else
    info "Adding $ARDUINO_DIR/ to .gitignore"
    echo "" >> "$GITIGNORE"
    echo "# Arduino core (downloaded)" >> "$GITIGNORE"
    echo "$ARDUINO_DIR/" >> "$GITIGNORE"
    success ".gitignore updated"
fi