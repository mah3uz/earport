import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

// Same look as ToggleSetting, but the value lives on the AirPods, not in plugin settings
Row {
    id: root

    required property string label
    property string description: ""
    property bool checked: false

    signal toggled(bool checked)

    width: parent.width
    spacing: Theme.spacingM
    opacity: enabled ? 1 : 0.5

    Column {
        width: parent.width - toggle.width - Theme.spacingM
        spacing: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter

        StyledText {
            text: root.label
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            text: root.description
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.description !== ""
        }
    }

    DToggle {
        id: toggle
        anchors.verticalCenter: parent.verticalCenter
        checked: root.checked
        onToggled: isChecked => root.toggled(isChecked)
    }
}
