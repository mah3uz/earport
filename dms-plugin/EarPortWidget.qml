import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "earport.js" as EarPort

PluginComponent {
    id: root

    readonly property var daemon: PluginService.pluginDaemonInstances["earport"] ?? null
    readonly property var s: daemon?.state ?? ({
            "available": false
        })
    readonly property bool available: s.available === true
    readonly property bool connected: available && s.Connected === true
    readonly property var lowest: available ? EarPort.lowest(s) : null
    readonly property color levelColor: {
        if (!lowest || lowest.charging || lowest.level > 20)
            return Theme.widgetTextColor;
        return lowest.level <= 10 ? Theme.error : Theme.warning;
    }
    readonly property int barIcon: Theme.barIconSize(barThickness, undefined, barConfig?.maximizeWidgetIcons, barConfig?.iconScale)
    readonly property int barText: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)

    // Seen nearby (on the iPhone) keeps the pill, dimmed: its battery is still worth a glance
    _visibilityOverride: true
    _visibilityOverrideValue: connected || lowest !== null

    popoutWidth: 400

    ccWidgetIcon: EarPort.headphones(s) ? "headphones" : "earbuds"
    ccWidgetPrimaryText: EarPort.name(s)
    ccWidgetSecondaryText: {
        if (!connected || s.AudioSource === "other")
            return EarPort.status(s);
        const parts = [];
        if (s.SupportsANC)
            parts.push(EarPort.modeNames[s.NoiseControlMode] ?? "");
        if (lowest)
            parts.push(lowest.level + "%");
        return parts.filter(p => p).join(" · ") || EarPort.status(s);
    }
    ccWidgetIsActive: connected
    ccDetailHeight: 330

    onCcWidgetToggled: daemon?.cycleNoiseControlMode()

    ccDetailContent: Component {
        Rectangle {
            implicitHeight: detailPanel.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Theme.nestedSurface
            border.color: Theme.outlineMedium
            border.width: Theme.layerOutlineWidth

            Component.onCompleted: root.ccDetailHeight = Qt.binding(() => implicitHeight)

            EarPortPanel {
                id: detailPanel
                x: Theme.spacingL
                y: Theme.spacingL
                width: parent.width - Theme.spacingL * 2
                daemon: root.daemon
                onSettingsRequested: PopoutService.closeControlCenter()
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout

            EarPortPanel {
                width: parent.width
                topPadding: Theme.spacingS
                daemon: root.daemon
                onSettingsRequested: popout.closePopout?.()
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            opacity: root.connected ? 1 : 0.6

            AirPodsIcon {
                anchors.verticalCenter: parent.verticalCenter
                iconSize: root.barIcon
                model: root.s.DeviceModel ?? ""
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.lowest !== null

                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.lowest?.charging ?? false
                    name: "bolt"
                    size: root.barText
                    color: Theme.widgetTextColor
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.lowest?.level ?? 0) + "%"
                    font.pixelSize: root.barText
                    color: root.levelColor
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 1
            opacity: root.connected ? 1 : 0.6

            AirPodsIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                iconSize: root.barIcon
                model: root.s.DeviceModel ?? ""
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.lowest !== null
                text: root.lowest?.level ?? ""
                font.pixelSize: root.barText
                color: root.lowest?.charging ? Theme.success : root.levelColor
            }
        }
    }
}
