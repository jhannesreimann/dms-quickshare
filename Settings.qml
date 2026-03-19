import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "quickshare"

    StyledText {
        width: parent.width
        text: "Quick Share Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure file sharing with nearby devices"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "isEnabled"
        label: "Enable Quick Share"
        description: "Allow your device to be discovered and send files"
        defaultValue: true
    }
    
    ToggleSetting {
        settingKey: "autoAccept"
        label: "Auto-Accept Transfers"
        description: "Automatically accept files sent from any nearby device without asking"
        defaultValue: false
    }

    StringSetting {
        settingKey: "deviceName"
        label: "Device Name"
        description: "How your device appears to others (Not fully supported by daemon yet)"
        placeholder: "DankLinux PC"
        defaultValue: "DankLinux PC"
    }

    SelectionSetting {
        settingKey: "visibility"
        label: "Visibility"
        description: "Who can see this device"
        options: [
            {label: "Everyone", value: "everyone"},
            {label: "Contacts Only", value: "contacts"},
            {label: "Hidden", value: "hidden"}
        ]
        defaultValue: "everyone"
    }
}
