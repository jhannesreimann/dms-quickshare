# DankQuickShare

A native Quick Share (Nearby Share) integration for DankMaterialShell. It allows you to seamlessly send and receive files between your Linux PC and Android devices.

## Features
- **Send Files:** Select multiple files or just Drag & Drop them onto the Quick Share icon to push them to your Android device with a single click.
- **Receive Files:** Get an interactive native desktop notification when a nearby device wants to send you a file (Accept/Reject directly from the notification).
- **Auto-Accept:** Toggle "Auto-Accept Transfers" in the settings to automatically receive files from known devices without clicking anything.
- **Progress Tracking:** See live upload/download progress bars with exact megabyte counts inside the DankBar widget.
- **Native D-Bus Daemon:** Runs a lightweight Rust background process built on top of `rquickshare` for reliable, low-latency device discovery and transfers. Files are automatically saved to your `~/Downloads` folder.

## Architecture

This plugin follows the same architectural pattern as `DankKDEConnect`. It consists of two parts:
1. **The QML Frontend:** The beautiful UI that lives in your DankBar and Control Center.
2. **The Rust Daemon (`dms-quickshare-daemon`):** A headless D-Bus service that handles the actual Quick Share protocol (mDNS, Bluetooth LE, and TCP transfers).

## Installation

### 1. Install the Daemon
Before the plugin can work, you need to compile and install the Rust daemon. Ensure you have Rust and Cargo installed (`rustup`).

```bash
cd daemon
cargo build --release
# Move the binary to a folder in your PATH (e.g. /usr/local/bin)
sudo cp target/release/dms-quickshare-daemon /usr/local/bin/
```

### 2. Enable the Plugin
Open your DankMaterialShell Settings, navigate to the **Plugins** tab, click "Scan for Plugins", and toggle **Quick Share** on.

## Submitting to the Plugin Browser
To add this plugin to your DMS environment using the Plugin Browser:
1. Make sure you have this repository pushed to GitHub.
2. In the `dms-plugin-registry` repository, add a file named `yourname-quickshare.json` in the `plugins/` directory:
```json
{
    "id": "quickshare",
    "name": "Quick Share",
    "capabilities": ["dankbar-widget", "control-center"],
    "category": "utilities",
    "repo": "https://github.com/yourname/dms-quickshare",
    "author": "noaa",
    "description": "Send and receive files seamlessly across nearby devices using Quick Share.",
    "dependencies": ["dms-quickshare-daemon", "zenity", "libnotify"],
    "compositors": ["any"],
    "distro": ["any"],
    "screenshot": "https://raw.githubusercontent.com/yourname/dms-quickshare/main/screenshot.png"
}
```
3. Submit a Pull Request to the registry.

## Acknowledgements
Powered by the reverse-engineered Quick Share protocol from [rquickshare](https://github.com/Martichou/rquickshare).
