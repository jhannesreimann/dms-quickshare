# DankQuickShare

A native Quick Share (Nearby Share) integration for DankMaterialShell. It allows you to seamlessly send and receive files between your Linux PC and Android devices.

## Features
- **Send Files:** Select multiple files or just Drag & Drop them onto the Quick Share icon to push them to your Android device with a single click.
- **Receive Files:** Get an interactive native desktop notification when a nearby device wants to send you a file (Accept/Reject directly from the notification).
- **Auto-Accept:** Toggle "Auto-Accept Transfers" in the settings to automatically receive files from known devices without clicking anything.
- **Progress Tracking:** See live upload/download progress bars with exact megabyte counts inside the DankBar widget.
- **Native D-Bus Daemon:** Runs a lightweight Rust background process built on top of `rquickshare` for reliable, low-latency device discovery and transfers. Files are automatically saved to your `~/Downloads` folder.

## Architecture
This plugin works on **any Wayland compositor** (Hyprland, Niri, Sway, etc.) because it relies entirely on native Linux protocols. 
It consists of two parts:
1. **The QML Frontend:** The UI that lives in your DankBar and Control Center.
2. **The Rust Daemon (`dms-quickshare-daemon`):** A headless D-Bus service that handles the actual Quick Share protocol (mDNS, Bluetooth LE, and TCP transfers). The plugin will automatically start this daemon in the background.

## Installation

Because the Quick Share protocol requires compiling a native Rust daemon and needs Bluetooth, we provide a simple installer script.

1. Clone or download this plugin to your `~/.config/DankMaterialShell/plugins/` folder.
2. Navigate into the plugin folder:
   ```bash
   cd ~/.config/DankMaterialShell/plugins/DankQuickShare
   ```
3. Run the installer script:
   ```bash
   ./install.sh
   ```
   *This script will verify you have the required dependencies (`cargo`, `libnotify`, `bluez`) and compile the daemon into `~/.local/bin/`.*

4. Open your DankMaterialShell Settings, navigate to the **Plugins** tab, click "Scan for Plugins", and toggle **Quick Share** on.

### Manual Dependencies (If the script fails)
If you prefer to install things manually, ensure you have:
- `rustup` / `cargo` (to compile the daemon)
- `libnotify` (for interactive desktop notifications)
- `bluez` and `avahi` (for Bluetooth LE and mDNS discovery)

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
    "dependencies": ["dms-quickshare-daemon", "libnotify"],
    "compositors": ["any"],
    "distro": ["any"],
    "screenshot": "https://raw.githubusercontent.com/yourname/dms-quickshare/main/screenshot.png"
}
```
3. Submit a Pull Request to the registry.

## Acknowledgements
Powered by the reverse-engineered Quick Share protocol from [rquickshare](https://github.com/Martichou/rquickshare).
