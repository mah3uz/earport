import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Widgets

Column {
    id: root

    required property string key
    required property string label
    required property int level
    required property bool charging

    readonly property bool known: level >= 0
    readonly property color ringColor: charging ? Theme.success : level <= 10 ? Theme.error : level <= 20 ? Theme.warning : Theme.primary
    readonly property real diameter: Theme.iconSizeLarge * 2

    spacing: Theme.spacingXS
    width: Math.max(diameter, labelText.implicitWidth)

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.diameter
        height: root.diameter
        opacity: root.known ? 1 : 0.5

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.withAlpha(root.known ? root.ringColor : Theme.surfaceText, 0.25)
                strokeWidth: 4
                PathAngleArc {
                    centerX: root.diameter / 2
                    centerY: root.diameter / 2
                    radiusX: root.diameter / 2 - 2
                    radiusY: root.diameter / 2 - 2
                    startAngle: -90
                    sweepAngle: 360
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.known && root.level > 0 ? root.ringColor : "transparent"
                strokeWidth: 4
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.diameter / 2
                    centerY: root.diameter / 2
                    radiusX: root.diameter / 2 - 2
                    radiusY: root.diameter / 2 - 2
                    startAngle: -90
                    sweepAngle: 3.6 * Math.min(root.level, 100)
                }
            }
        }

        DankIcon {
            anchors.centerIn: parent
            visible: root.key === "headphones"
            name: "headphones"
            size: Theme.iconSize
            color: Theme.surfaceText
        }

        TintedIcon {
            anchors.centerIn: parent
            visible: root.key !== "headphones"
            name: root.key === "headphones" ? "case" : root.key
            size: Theme.iconSize
            color: Theme.surfaceText
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        DankIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.charging
            name: "bolt"
            size: Theme.iconSizeSmall
            color: Theme.success
        }

        StyledText {
            text: root.known ? root.level + "%" : "—"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Bold
            color: Theme.surfaceText
        }
    }

    StyledText {
        id: labelText
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
