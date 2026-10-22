import QtQuick
import QtQuick.Effects

// The SVG only supplies the shape: its alpha masks a fill in the theme colour.
Item {
    id: root

    required property string name
    property int size: 16
    property color color: "white"

    implicitWidth: size
    implicitHeight: size

    Image {
        id: mask
        anchors.fill: parent
        source: Qt.resolvedUrl("icons/earport-" + root.name + "-symbolic.svg")
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        smooth: true
        visible: false
        layer.enabled: true
    }

    Rectangle {
        anchors.fill: parent
        color: root.color
        layer.enabled: true
        layer.effect: MultiEffect {
            // Threshold 0.5 with spread 1 maps the mask alpha linearly onto 0..1
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }
}
