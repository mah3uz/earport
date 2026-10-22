import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DankCommon.Widgets as DankCommon
import "earport.js" as EarPort

Column {
    id: root

    required property var daemon
    readonly property var s: daemon?.state ?? ({
            "available": false
        })
    readonly property bool available: s.available === true
    readonly property bool connected: available && s.Connected === true
    readonly property var modes: EarPort.modes(s)
    readonly property string listeningText: connected ? EarPort.listeningTime(s.ListeningTimeRemaining) : ""
    readonly property string installUrl: "https://github.com/Anoryth/earport"

    signal settingsRequested

    spacing: Theme.spacingM

    function openSettings() {
        settingsRequested();
        PopoutService.openSettingsWithTab("plugins");
        Qt.callLater(() => PopoutService.settingsModal?.openPluginSettings("earport"));
    }

    function copyInstallCommand() {
        Quickshell.execDetached(["dms", "cl", "copy", `curl -fsSL ${installUrl}/releases/latest/download/install-daemon.sh | bash`]);
        ToastService.showInfo("Installation command copied", "Paste it in a terminal to install or update the EarPort service");
    }

    Item {
        width: parent.width
        height: Math.max(badge.height, title.implicitHeight)

        Rectangle {
            id: badge
            width: Theme.iconSize * 2
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.connected ? Theme.primary : Theme.surfaceContainerHighest

            AirPodsIcon {
                anchors.centerIn: parent
                iconSize: Theme.iconSize
                model: root.s.DeviceModel ?? ""
                color: root.connected ? Theme.primaryText : Theme.surfaceVariantText
            }
        }

        Column {
            id: title
            anchors.left: badge.right
            anchors.leftMargin: Theme.spacingM
            anchors.right: settingsButton.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                width: parent.width
                text: EarPort.name(root.s)
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: EarPort.status(root.s)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
            }
        }

        DankActionButton {
            id: settingsButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.available
            iconName: "settings"
            tooltipText: "EarPort Settings"
            onClicked: root.openSettings()
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS
        visible: root.available

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingXL

            Repeater {
                model: EarPort.batteries(root.s)

                BatteryRing {
                    required property var modelData
                    key: modelData.key
                    label: modelData.label
                    level: modelData.level
                    charging: modelData.charging
                }
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.listeningText !== ""
            text: root.listeningText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    Row {
        id: modeRow
        width: parent.width
        spacing: Theme.spacingS
        visible: root.available && root.modes.length > 0
        opacity: root.connected ? 1 : 0.5

        Repeater {
            model: root.modes

            Rectangle {
                id: modeButton

                required property string modelData
                readonly property bool selected: root.connected && root.s.NoiseControlMode === modelData
                readonly property color ink: selected ? Theme.primaryText : Theme.surfaceText

                width: (modeRow.width - modeRow.spacing * (root.modes.length - 1)) / root.modes.length
                height: Theme.iconSize * 3
                radius: Theme.cornerRadius
                color: selected ? Theme.primary : Theme.surfaceContainerHighest
                activeFocusOnTab: root.connected
                Accessible.role: Accessible.RadioButton
                Accessible.name: EarPort.modeNames[modelData]
                Accessible.checked: selected

                function choose() {
                    if (root.connected && !selected)
                        root.daemon.setNoiseControlMode(modelData);
                }

                Keys.onSpacePressed: choose()
                Keys.onReturnPressed: choose()

                DankCommon.FocusRing {}

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    TintedIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "nc-" + modeButton.modelData
                        size: Theme.iconSize
                        color: modeButton.ink
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ({
                                "off": "Off",
                                "anc": "Noise Cancel",
                                "transparency": "Transparency",
                                "adaptive": "Adaptive"
                            })[modeButton.modelData]
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: modeButton.selected ? Font.Bold : Font.Medium
                        color: modeButton.ink
                    }
                }

                StateLayer {
                    disabled: !root.connected
                    stateColor: modeButton.ink
                    onClicked: modeButton.choose()
                }
            }
        }
    }

    DankToggle {
        visible: root.connected
        text: "Conversation Awareness"
        description: "Lower the volume when you speak"
        checked: root.s.ConversationalAwareness === true
        onToggled: checked => root.daemon.setConversationalAwareness(checked)
    }

    DankButton {
        width: parent.width
        visible: root.connected && root.s.AudioSource === "other"
        iconName: "computer"
        text: "Use on This Computer"
        onClicked: root.daemon.claimAudio()
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM
        visible: !root.available

        StyledText {
            width: parent.width
            text: "EarPort needs its background service to talk to your AirPods. Install it, or start it if it is installed."
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Row {
            spacing: Theme.spacingS

            DankButton {
                iconName: "help"
                text: "How to Install"
                onClicked: Qt.openUrlExternally(root.installUrl + "#installation")
            }

            DankButton {
                iconName: "content_copy"
                text: "Copy Command"
                backgroundColor: Theme.surfaceContainerHigh
                textColor: Theme.surfaceText
                onClicked: root.copyInstallCommand()
            }
        }
    }
}
