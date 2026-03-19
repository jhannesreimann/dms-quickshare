#!/usr/bin/env bash

set -e

echo "=============================================="
echo "  DankQuickShare - Installer Script"
echo "=============================================="

# 1. Check for basic system dependencies
echo "Checking system dependencies..."
DEPS_MISSING=0

command -v notify-send >/dev/null 2>&1 || { echo >&2 "Missing 'notify-send' (usually part of libnotify or libnotify-bin)."; DEPS_MISSING=1; }
command -v cargo >/dev/null 2>&1 || { echo >&2 "Missing 'cargo' (Rust compiler). Please install rustup: https://rustup.rs/"; DEPS_MISSING=1; }
command -v bluetoothctl >/dev/null 2>&1 || { echo >&2 "Missing 'bluetoothctl' (bluez). Quick Share requires Bluetooth LE."; DEPS_MISSING=1; }

if [ $DEPS_MISSING -eq 1 ]; then
    echo ""
    echo "Please install the missing dependencies using your package manager."
    echo "Ubuntu/Fedora: sudo apt/dnf install libnotify-bin bluez cargo"
    echo "Arch Linux: sudo pacman -S libnotify bluez rust"
    exit 1
fi

echo "All system dependencies found!"
echo ""

# 2. Build the Rust Daemon
echo "Building dms-quickshare-daemon (this might take a minute)..."
cd daemon
cargo build --release
cd ..

# 3. Install the Daemon to the user's local bin path
echo "Installing daemon to ~/.local/bin/ ..."
mkdir -p ~/.local/bin
cp daemon/target/release/dms-quickshare-daemon ~/.local/bin/

# Ensure ~/.local/bin is in PATH for the current session (for the plugin to find it)
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "WARNING: ~/.local/bin is not in your PATH."
    echo "Please add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your ~/.bashrc or ~/.zshrc"
fi

# 4. Success Message
echo ""
echo "=============================================="
echo "Installation Successful!"
echo "=============================================="
echo "1. The daemon is installed in ~/.local/bin/dms-quickshare-daemon"
echo "2. You can now enable 'Quick Share' in the DankMaterialShell Settings."
echo "Note: Ensure your Bluetooth and Avahi (mDNS) services are running so devices can discover your PC."
