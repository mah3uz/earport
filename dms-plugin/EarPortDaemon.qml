import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    property string pluginId: "earport"
    property var pluginService: null

    readonly property string busName: "io.github.anoryth.EarPort"
    readonly property string objectPath: "/io/github/anoryth/EarPort"
    readonly property string ifaceName: "io.github.anoryth.EarPort1"
    readonly property string unknownName: "Unknown AirPods"
    readonly property int disconnectNoticeMs: 5000
    readonly property int lowerMs: 400
    readonly property int restoreMs: 1500
    readonly property int fadeStepMs: 20
    readonly property real volumeTolerance: 0.01

    property var _state: ({
            "available": false,
            "speaking": false
        })
    readonly property var state: _state

    readonly property bool _bridgeReady: DMSService.isConnected && DMSService.capabilities.includes("dbus")
    property bool _subscribed: false
    property var _lowNotified: ({
            "left": false,
            "right": false
        })
    property var _quietDisconnect: null
    property bool _heldDnd: false
    property var _fade: null

    function _get(key, fallback) {
        return pluginService ? pluginService.loadPluginData(pluginId, key, fallback) : fallback;
    }

    function _patch(changes) {
        _state = Object.assign({}, _state, changes);
    }

    function _call(method, args) {
        if (!_bridgeReady)
            return;
        DMSService.dbusCall("session", busName, objectPath, ifaceName, method, args, response => {
            if (response.error)
                console.warn("EarPort:", method, "failed:", response.error);
        });
    }

    // The bridge sends whole numbers as uint32 and cannot build a variant, which the daemon rejects.
    function _busctl(method, signature, values) {
        _run(["busctl", "--user", "call", busName, objectPath, ifaceName, method, signature].concat(values));
    }

    function _run(command) {
        const proc = processComponent.createObject(root, {
            "command": command
        });
        proc.running = true;
    }

    function setNoiseControlMode(mode) {
        _call("SetNoiseControlMode", [mode]);
    }

    function cycleNoiseControlMode() {
        const s = _state;
        if (!s.Connected || !s.SupportsANC)
            return;
        const enabled = {
            "anc": s.ListeningModeANC !== false,
            "transparency": s.ListeningModeTransparency !== false,
            "adaptive": s.ListeningModeAdaptive !== false && (s.SupportsAdaptive || false),
            "off": s.ListeningModeOff === true
        };
        const cycle = ["anc", "transparency", "adaptive", "off"].filter(m => enabled[m]);
        if (cycle.length < 2)
            return;
        setNoiseControlMode(cycle[(cycle.indexOf(s.NoiseControlMode) + 1) % cycle.length]);
    }

    function setConversationalAwareness(enabled) {
        _call("SetConversationalAwareness", [!!enabled]);
    }

    function setAdaptiveNoiseLevel(level) {
        _busctl("SetAdaptiveNoiseLevel", "i", [String(Math.round(level))]);
    }

    function setEarPauseMode(mode) {
        _busctl("SetEarPauseMode", "i", [String(Math.round(mode))]);
    }

    function setListeningModes(off, transparency, anc, adaptive) {
        _call("SetListeningModes", [!!off, !!transparency, !!anc, !!adaptive]);
    }

    function setSetting(key, value) {
        const current = _state.Settings ? _state.Settings[key] : undefined;
        const kind = current !== undefined ? typeof current : typeof value;
        if (kind === "boolean")
            _busctl("SetSetting", "sv", [key, "b", value ? "true" : "false"]);
        else
            _busctl("SetSetting", "sv", [key, "i", String(Math.round(value))]);
    }

    function setAutoConnect(enabled) {
        _call("SetAutoConnect", [!!enabled]);
    }

    function setAppleHandoff(enabled) {
        _call("SetAppleHandoff", [!!enabled]);
    }

    function setDisplayName(name) {
        _call("SetDisplayName", [name]);
    }

    function claimAudio() {
        _call("ClaimAudio", []);
    }

    function _notify(title, body, urgent) {
        const cmd = ["notify-send", "-a", "EarPort", "-i", "audio-headphones-symbolic"];
        if (urgent)
            cmd.push("-u", "critical");
        cmd.push(title);
        if (body)
            cmd.push(body);
        _run(cmd);
    }

    function _displayName(name) {
        const cached = _state.DisplayName;
        if (cached && cached !== unknownName)
            return cached;
        return name || _state.DeviceModel || "AirPods";
    }

    function _start() {
        if (_subscribed || !_bridgeReady)
            return;
        _subscribed = true;
        signalMonitor.running = true;
        _refresh();
    }

    function _stop() {
        _subscribed = false;
        signalMonitor.running = false;
        monitorRestartTimer.stop();
        _daemonGone();
    }

    function _refresh() {
        DMSService.dbusGetAllProperties("session", busName, objectPath, ifaceName, response => {
            if (response.error || !response.result) {
                _daemonGone();
                return;
            }
            const props = response.result.values?.[0] ?? response.result;
            _state = Object.assign({}, props, {
                "available": true,
                "speaking": false
            });
            const threshold = _get("lowBatteryThreshold", 20);
            _lowNotified = {
                "left": props.BatteryLeft > 0 && props.BatteryLeft <= threshold,
                "right": props.BatteryRight > 0 && props.BatteryRight <= threshold
            };
        });
    }

    function _daemonGone() {
        _endConversation();
        _quietDisconnect = null;
        disconnectTimer.stop();
        _state = {
            "available": false,
            "speaking": false
        };
    }

    function _unwrap(variant) {
        if (variant === null || typeof variant !== "object" || !("type" in variant))
            return variant;
        if (variant.type !== "a{sv}")
            return variant.data;
        const out = {};
        for (const key in variant.data)
            out[key] = _unwrap(variant.data[key]);
        return out;
    }

    function _onSignal(line) {
        let message;
        try {
            message = JSON.parse(line);
        } catch (e) {
            return;
        }
        const body = message.payload?.data ?? [];
        if (message.member === "NameOwnerChanged") {
            if (body[2])
                _refresh();
            else
                _daemonGone();
        } else if (message.member === "PropertiesChanged") {
            if (body[0] !== ifaceName)
                return;
            const changed = {};
            for (const key in body[1])
                changed[key] = _unwrap(body[1][key]);
            _onPropertiesChanged(changed);
        } else if (message.interface === ifaceName) {
            _onDaemonSignal(message.member, body);
        }
    }

    function _onPropertiesChanged(changed) {
        _patch(changed);
        _noticeDisconnection();
        if ("BatteryLeft" in changed || "BatteryRight" in changed)
            _checkLowBattery();
    }

    function _onDaemonSignal(member, body) {
        if (member === "DeviceConnected") {
            _lowNotified = {
                "left": false,
                "right": false
            };
            if (_quietDisconnect) {
                _quietDisconnect = null;
                disconnectTimer.stop();
            } else if (_get("enableConnectionNotifications", true)) {
                _notify(_displayName(body[1]) + " Connected", "", false);
            }
        } else if (member === "DeviceDisconnected") {
            _quietDisconnect = {
                "name": body[1]
            };
            disconnectTimer.restart();
        } else if (member === "SpeakingChanged") {
            _onSpeaking(!!body[0]);
        } else if (member === "PausedForSleep") {
            _notify("Playback Paused", "You seemed to have fallen asleep, so playback was paused.", false);
        }
    }

    function _noticeDisconnection() {
        if (!_quietDisconnect || disconnectTimer.running || _state.Reconnecting)
            return;
        const name = _quietDisconnect.name;
        _quietDisconnect = null;
        if (_get("enableConnectionNotifications", true))
            _notify(_displayName(name) + " Disconnected", "", false);
    }

    function _crossedLow(pod, level, threshold) {
        if (level > threshold) {
            _lowNotified[pod] = false;
            return false;
        }
        if (level <= 0 || _lowNotified[pod])
            return false;
        _lowNotified[pod] = true;
        return true;
    }

    // AirPods Max have a single battery, reported as the left one
    function _checkLowBattery() {
        if (!_get("enableLowBatteryNotifications", true))
            return;
        const s = _state;
        const threshold = _get("lowBatteryThreshold", 20);
        const parts = [];
        if (_crossedLow("left", s.BatteryLeft, threshold))
            parts.push((s.IsHeadphones ? "Battery" : "Left") + ": " + s.BatteryLeft + "%");
        if (!s.IsHeadphones && _crossedLow("right", s.BatteryRight, threshold))
            parts.push("Right: " + s.BatteryRight + "%");
        if (parts.length > 0)
            _notify((s.DisplayName || s.DeviceModel || "AirPods") + " Low Battery", parts.join(", "), true);
    }

    function _onSpeaking(speaking) {
        _patch({
            "speaking": speaking
        });
        if (speaking) {
            if (_state.ConversationalAwareness)
                _lower();
            _holdNotifications(true);
        } else {
            _restore();
            _holdNotifications(false);
        }
    }

    function _endConversation() {
        if (_fade) {
            fadeTimer.stop();
            if (_untouched())
                _fade.sink.audio.volume = _fade.saved;
            _fade = null;
        }
        _holdNotifications(false);
    }

    function _holdNotifications(hold) {
        if (hold) {
            if (_heldDnd || SessionData.doNotDisturb || !_get("holdNotificationsDuringConversations", true))
                return;
            _heldDnd = true;
            SessionData.setDoNotDisturb(true, 0);
        } else if (_heldDnd) {
            _heldDnd = false;
            if (SessionData.doNotDisturb)
                SessionData.setDoNotDisturb(false, 0);
        }
    }

    function _airPodsSink() {
        const sink = AudioService.sink;
        const address = _state.DeviceAddress;
        if (!sink || !sink.audio || !address)
            return null;
        const prefix = "BLUEZ_OUTPUT." + address.replace(/:/g, "_").toUpperCase();
        return (sink.name || "").toUpperCase().startsWith(prefix) ? sink : null;
    }

    function _ease(t) {
        return t * t * (3 - 2 * t);
    }

    function _lower() {
        if (_fade) {
            if (_fade.restoring)
                _fadeTo(_fade.lowered, lowerMs, false);
            return;
        }
        const sink = _airPodsSink();
        if (!sink)
            return;
        const saved = sink.audio.volume;
        const lowered = saved * _get("conversationVolume", 20) / 100;
        _fade = {
            "sink": sink,
            "saved": saved,
            "lowered": lowered,
            "expected": saved,
            "previous": saved
        };
        _fadeTo(lowered, lowerMs, false);
    }

    function _restore() {
        if (!_fade || _fade.restoring)
            return;
        if (!_untouched()) {
            _fade = null;
            fadeTimer.stop();
            return;
        }
        _fadeTo(_fade.saved, restoreMs, true);
    }

    function _fadeTo(target, duration, restoring) {
        const f = _fade;
        f.start = f.sink.audio.volume;
        f.target = target;
        f.steps = Math.max(1, Math.round(duration / fadeStepMs));
        f.step = 0;
        f.restoring = restoring;
        fadeTimer.restart();
    }

    // The sink may report the previous step's value until PipeWire confirms the write
    function _untouched() {
        const f = _fade;
        if (!f || f.sink !== AudioService.sink || !f.sink.audio)
            return false;
        const v = f.sink.audio.volume;
        return Math.abs(v - f.expected) <= volumeTolerance || Math.abs(v - f.previous) <= volumeTolerance;
    }

    function _fadeStep() {
        const f = _fade;
        if (!f || !_untouched()) {
            fadeTimer.stop();
            _fade = null;
            return;
        }
        f.step++;
        f.previous = f.expected;
        f.expected = f.start + (f.target - f.start) * _ease(f.step / f.steps);
        f.sink.audio.volume = f.expected;
        if (f.step >= f.steps) {
            fadeTimer.stop();
            if (f.restoring)
                _fade = null;
        }
    }

    Timer {
        id: fadeTimer
        interval: root.fadeStepMs
        repeat: true
        onTriggered: root._fadeStep()
    }

    Timer {
        id: disconnectTimer
        interval: root.disconnectNoticeMs
        onTriggered: root._noticeDisconnection()
    }

    Component {
        id: processComponent

        Process {
            stderr: StdioCollector {
                onStreamFinished: {
                    if (text.trim())
                        console.warn("EarPort:", text.trim());
                }
            }
            onExited: destroy()
        }
    }

    // Not DMSService.dbusSubscribe: DMS 1.6 loses D-Bus subscriptions for good when it reopens its event stream, as opening Settings does
    Process {
        id: signalMonitor
        command: ["busctl", "--user", "monitor", "--json=short", "--match", "type='signal',sender='" + root.busName + "'", "--match", "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='" + root.busName + "'"]
        stdout: SplitParser {
            onRead: line => root._onSignal(line)
        }
        onExited: {
            if (root._subscribed)
                monitorRestartTimer.start();
        }
    }

    Timer {
        id: monitorRestartTimer
        interval: 2000
        onTriggered: {
            if (root._subscribed)
                signalMonitor.running = true;
        }
    }

    Connections {
        target: DMSService
        function onConnectionStateChanged() {
            if (!DMSService.isConnected && root._subscribed)
                root._stop();
        }
        function onCapabilitiesReceived() {
            root._start();
        }
    }

    on_BridgeReadyChanged: _start()

    Component.onCompleted: _start()

    Component.onDestruction: {
        if (_subscribed)
            _stop();
    }
}
