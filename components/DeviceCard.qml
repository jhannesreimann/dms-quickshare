import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

StyledRect {
    id: root
    
    property string deviceId
    property string deviceName
    property string ip
    property string deviceType: "phone"
    
    signal clicked()

    width: parent.width
    height: 60
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHighest
    
    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingM

        DankIcon {
            name: root.deviceType === "phone" ? "smartphone" : "tablet_mac"
            size: Theme.iconSizeLarge
            color: Theme.primary
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            text: root.deviceName
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
