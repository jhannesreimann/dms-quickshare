pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Services

Singleton {
    id: root

    readonly property string service: "org.danklinux.QuickShare"
    readonly property string daemonPath: "/org/danklinux/QuickShare"
    readonly property string daemonInterface: "org.danklinux.QuickShare"

    property bool available: false
    property bool isScanning: false

    // D-Bus signals that the UI can connect to
    signal deviceDiscovered(string id, string name, string ip)
    signal transferRequested(string id, string deviceName, string pin)
    signal transferProgress(string id, string state, int bytesAck, int bytesTotal)

    // Method to check if daemon is running
    function checkDaemon(callback) {
        Quickshell.exec(["pgrep", "-f", "dms-quickshare-daemon"], function(out, err, code) {
            root.available = (code === 0);
            if (callback) callback(root.available);
        });
    }

    // Call D-Bus methods safely
    function _callMethod(methodName, args, callback) {
        if (!root.available) {
            console.error("QuickShareService: Daemon is not running, cannot call " + methodName);
            if (callback) callback({ error: "Daemon not running" });
            return;
        }

        let cmd = [
            "gdbus", "call", "--session", 
            "--dest", root.service, 
            "--object-path", root.daemonPath, 
            "--method", root.daemonInterface + "." + methodName
        ].concat(args || []);

        Quickshell.exec(cmd, function(out, err, code) {
            if (callback) {
                if (code !== 0) callback({ error: err });
                else callback({ result: out });
            }
        });
    }

    function _callMethodDetached(methodName, args) {
        if (!root.available) return;
        
        let cmd = [
            "dbus-send", "--session", "--type=method_call", 
            "--dest=" + root.service, 
            root.daemonPath, 
            root.daemonInterface + "." + methodName
        ].concat(args || []);
        
        Quickshell.execDetached(cmd);
    }

    function setVisibility(visible) {
        _callMethodDetached("SetVisibility", ["boolean:" + (visible ? "true" : "false")]);
    }

    function startDiscovery() {
        root.isScanning = true;
        _callMethodDetached("StartDiscovery", []);
        // Reset scanning state after 15 seconds (daemon timeout)
        let timer = Qt.createQmlObject('import QtQuick; Timer { interval: 15000; running: true; onTriggered: root.isScanning = false }', root);
    }

    function acceptTransfer(transferId) {
        _callMethodDetached("AcceptTransfer", ["string:" + transferId]);
    }

    function rejectTransfer(transferId) {
        _callMethodDetached("RejectTransfer", ["string:" + transferId]);
    }

    function sendFiles(deviceId, deviceName, ipAddr, filesArray) {
        // Format array for gdbus
        let formattedFiles = "['" + filesArray.join("', '") + "']";
        _callMethod("SendFiles", ["'" + deviceId + "'", "'" + deviceName + "'", "'" + ipAddr + "'", formattedFiles]);
    }

    // Initialize D-Bus subscriptions
    Component.onCompleted: {
        checkDaemon();

        if (DMSService) {
            DMSService.dbusSubscribe("session", root.service, root.daemonPath, root.daemonInterface, "DeviceDiscovered", (response) => {
                if (response && response.result) {
                    root.deviceDiscovered(response.result.arguments[0], response.result.arguments[1], response.result.arguments[2]);
                }
            });

            DMSService.dbusSubscribe("session", root.service, root.daemonPath, root.daemonInterface, "TransferRequested", (response) => {
                if (response && response.result) {
                    root.transferRequested(response.result.arguments[0], response.result.arguments[1], response.result.arguments[2]);
                }
            });

            DMSService.dbusSubscribe("session", root.service, root.daemonPath, root.daemonInterface, "TransferProgress", (response) => {
                if (response && response.result) {
                    root.transferProgress(response.result.arguments[0], response.result.arguments[1], response.result.arguments[2] || 0, response.result.arguments[3] || 0);
                }
            });
        }
    }
}
