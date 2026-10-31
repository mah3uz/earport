import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "earport"

    readonly property var daemon: PluginService.pluginDaemonInstances["earport"] ?? null
    readonly property var s: daemon?.state ?? ({
            "available": false
        })
    readonly property bool available: s.available === true
    readonly property bool connected: available && s.Connected === true
    readonly property var deviceSettings: connected ? (s.Settings ?? {}) : {}
    readonly property string modelName: s.DeviceModel || "AirPods"
    readonly property string savedName: connected && s.DisplayName && s.DisplayName !== modelName ? s.DisplayName : ""
    readonly property var pauseModes: ["Off", "One earbud out", "Both earbuds out"]

    onSavedNameChanged: {
        if (!nameField.activeFocus)
            nameField.text = savedName;
    }

    function setListeningMode(key, enabled) {
        const next = {
            "off": s.ListeningModeOff === true,
            "transparency": s.ListeningModeTransparency !== false,
            "anc": s.ListeningModeANC !== false,
            "adaptive": s.ListeningModeAdaptive !== false && s.SupportsAdaptive === true
        };
        next[key] = enabled;
        if (Object.values(next).filter(v => v).length < 2) {
            ToastService.showWarning("At least two modes must stay in the cycle");
            return;
        }
        daemon.setListeningModes(next.off, next.transparency, next.anc, next.adaptive);
    }

    function saveName() {
        daemon.setDisplayName(nameField.text.trim());
        nameField.focus = false;
    }

    component SectionTitle: Column {
        property alias text: heading.text
        property alias description: detail.text

        width: parent.width
        topPadding: Theme.spacingM
        spacing: Theme.spacingXS

        StyledText {
            id: heading
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            id: detail
            width: parent.width
            visible: text !== ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    component StatusLine: Row {
        property alias icon: glyph.name
        property alias label: caption.text
        property alias value: valueText.text

        width: parent.width
        spacing: Theme.spacingM

        DIcon {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            size: Theme.iconSize
            color: Theme.surfaceVariantText
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                id: caption
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                id: valueText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }

    SectionTitle {
        text: "Device"
        topPadding: 0
    }

    StatusLine {
        icon: "bluetooth"
        label: "Connection"
        value: {
            if (!root.available)
                return "Service not running";
            return root.connected ? "Connected: " + (root.s.DisplayName || root.modelName) : "Disconnected";
        }
    }

    StatusLine {
        icon: "hearing"
        label: "Ear Detection"
        value: {
            if (!root.connected)
                return "No device connected";
            const ear = inEar => inEar ? "In ear" : "Out";
            if (root.s.IsHeadphones)
                return ear(root.s.LeftInEar || root.s.RightInEar);
            return "Left: " + ear(root.s.LeftInEar) + ", Right: " + ear(root.s.RightInEar);
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS
        enabled: root.connected
        opacity: enabled ? 1 : 0.5

        StyledText {
            text: "Custom Name"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Empty uses the model name"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DTextField {
                id: nameField
                width: parent.width - (saveButton.visible ? saveButton.width + parent.spacing : 0)
                placeholderText: root.modelName
                maximumLength: 64
                onAccepted: root.saveName()
                Component.onCompleted: text = root.savedName
            }

            DButton {
                id: saveButton
                anchors.verticalCenter: parent.verticalCenter
                visible: nameField.text.trim() !== root.savedName
                text: "Save"
                onClicked: root.saveName()
            }
        }
    }

    SectionTitle {
        text: "Conversations"
    }

    DeviceToggle {
        id: awarenessToggle
        enabled: root.connected
        label: "Conversation Awareness"
        description: "Lowers the volume when you speak"
        checked: root.s.ConversationalAwareness === true
        onToggled: checked => root.daemon.setConversationalAwareness(checked)
    }

    SliderSetting {
        settingKey: "conversationVolume"
        label: "Volume During Conversations"
        description: "Volume kept while you speak"
        defaultValue: 20
        minimum: 0
        maximum: 80
        unit: "%"
        enabled: awarenessToggle.checked
        opacity: enabled ? 1 : 0.5
    }

    ToggleSetting {
        settingKey: "holdNotificationsDuringConversations"
        label: "Hold Notifications During Conversations"
        description: "Do Not Disturb while you speak"
        defaultValue: true
        enabled: awarenessToggle.checked
        opacity: enabled ? 1 : 0.5
    }

    SectionTitle {
        text: "Noise Control"
        visible: !root.connected || root.s.SupportsANC === true
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS
        visible: root.s.SupportsAdaptive === true
        enabled: root.connected
        opacity: enabled ? 1 : 0.5

        StyledText {
            text: "Adaptive Noise Level"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Outside sound let through in Adaptive"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        DSlider {
            width: parent.width
            value: root.s.AdaptiveNoiseLevel ?? 50
            minimum: 0
            maximum: 100
            unit: ""
            wheelEnabled: false
            thumbOutlineColor: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
            onSliderValueChanged: newValue => {
                adaptiveDebounce.level = newValue;
                adaptiveDebounce.restart();
            }
        }
    }

    Timer {
        id: adaptiveDebounce
        property int level: 0
        interval: 300
        onTriggered: root.daemon?.setAdaptiveNoiseLevel(level)
    }

    SectionTitle {
        text: "Press and Hold"
        description: "Modes the stem and tile cycle through, at least two"
        visible: root.s.SupportsANC === true || !root.connected
    }

    DeviceToggle {
        enabled: root.connected
        visible: root.s.SupportsANC === true || !root.connected
        label: "Off"
        checked: root.s.ListeningModeOff === true
        onToggled: checked => root.setListeningMode("off", checked)
    }

    DeviceToggle {
        enabled: root.connected
        visible: root.s.SupportsANC === true || !root.connected
        label: "Transparency"
        checked: root.s.ListeningModeTransparency !== false && root.connected
        onToggled: checked => root.setListeningMode("transparency", checked)
    }

    DeviceToggle {
        enabled: root.connected
        visible: root.s.SupportsANC === true || !root.connected
        label: "Noise Cancellation"
        checked: root.s.ListeningModeANC !== false && root.connected
        onToggled: checked => root.setListeningMode("anc", checked)
    }

    DeviceToggle {
        enabled: root.connected
        visible: root.s.SupportsAdaptive === true
        label: "Adaptive"
        checked: root.s.ListeningModeAdaptive === true
        onToggled: checked => root.setListeningMode("adaptive", checked)
    }

    SectionTitle {
        text: "Media and Connection"
    }

    DDropdown {
        width: parent.width
        enabled: root.available
        opacity: enabled ? 1 : 0.5
        text: "Auto-Pause Media"
        description: "When earbuds come out"
        options: root.pauseModes
        currentValue: root.pauseModes[root.s.EarPauseMode ?? 0] ?? root.pauseModes[0]
        onValueChanged: value => root.daemon.setEarPauseMode(root.pauseModes.indexOf(value))
    }

    DeviceToggle {
        visible: typeof root.s.AutoConnect === "boolean"
        label: "Automatic Connection"
        description: "When worn or playing, unless in use elsewhere"
        checked: root.s.AutoConnect === true
        onToggled: checked => root.daemon.setAutoConnect(checked)
    }

    DeviceToggle {
        visible: typeof root.s.AppleHandoff === "boolean"
        label: "Switch With Your Apple Devices"
        description: "Experimental. Follow you between here and your Apple devices"
        checked: root.s.AppleHandoff === true
        onToggled: checked => root.daemon.setAppleHandoff(checked)
    }

    SectionTitle {
        text: "Notifications"
    }

    ToggleSetting {
        settingKey: "enableConnectionNotifications"
        label: "Connection Notifications"
        description: "On connect and disconnect"
        defaultValue: true
    }

    ToggleSetting {
        id: lowBatteryToggle
        settingKey: "enableLowBatteryNotifications"
        label: "Low Battery Notifications"
        description: "When an earbud drops below the threshold"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "lowBatteryThreshold"
        label: "Low Battery Threshold"
        defaultValue: 20
        minimum: 5
        maximum: 50
        unit: "%"
        enabled: lowBatteryToggle.value
        opacity: enabled ? 1 : 0.5
    }

    SectionTitle {
        text: "Stored on Your AirPods"
        description: root.connected ? "" : "Connect your AirPods to change these"
    }

    Repeater {
        model: [
            {
                "key": "OneBudANC",
                "label": "Noise Cancellation with One AirPod",
                "description": "With only one AirPod in"
            },
            {
                "key": "PersonalizedVolume",
                "label": "Personalized Volume",
                "description": "Adapts to your surroundings"
            },
            {
                "key": "SleepDetection",
                "label": "Pause Media When Falling Asleep",
                "description": "When you fall asleep"
            },
            {
                "key": "PressSpeed",
                "label": "Press Speed",
                "description": "For double and triple presses",
                "choices": ["Default", "Slower", "Slowest"]
            },
            {
                "key": "PressHoldDuration",
                "label": "Press and Hold Duration",
                "description": "Time to register a hold",
                "choices": ["Default", "Shorter", "Shortest"]
            },
            {
                "key": "VolumeSwipe",
                "label": "Volume Swipe",
                "description": "Swipe the stem to change volume"
            },
            {
                "key": "VolumeSwipeSpeed",
                "label": "Volume Swipe Duration",
                "description": "Delay between swipes",
                "choices": ["Default", "Longer", "Longest"]
            }
        ]

        Item {
            id: settingRow

            required property var modelData
            readonly property var value: root.deviceSettings[modelData.key]

            // The swipe duration only matters when swiping changes the volume
            enabled: modelData.key !== "VolumeSwipeSpeed" || root.deviceSettings.VolumeSwipe !== false
            visible: value !== undefined
            width: parent.width
            height: visible ? (modelData.choices ? choice.height : toggle.height) : 0

            DeviceToggle {
                id: toggle
                visible: !settingRow.modelData.choices
                label: settingRow.modelData.label
                description: settingRow.modelData.description
                checked: settingRow.value === true
                onToggled: checked => root.daemon.setSetting(settingRow.modelData.key, checked)
            }

            DDropdown {
                id: choice
                width: parent.width
                visible: !!settingRow.modelData.choices
                opacity: enabled ? 1 : 0.5
                text: settingRow.modelData.label
                description: settingRow.modelData.description
                options: settingRow.modelData.choices ?? []
                currentValue: options[settingRow.value] ?? ""
                onValueChanged: value => root.daemon.setSetting(settingRow.modelData.key, options.indexOf(value))
            }
        }
    }

    StyledText {
        width: parent.width
        topPadding: Theme.spacingM
        visible: root.available && !!root.s.Version
        text: "EarPort service " + root.s.Version
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
