.pragma library

const modeNames = {
    "off": "Noise Control Off",
    "anc": "Noise Cancellation",
    "transparency": "Transparency",
    "adaptive": "Adaptive"
};

function nearby(s) {
    const n = s.NearbyBattery || {};
    return !s.Connected && n.Left !== undefined ? n : null;
}

function name(s) {
    if (s.Connected)
        return s.DisplayName || s.DeviceModel || "AirPods";
    return nearby(s)?.Name || "AirPods";
}

function status(s) {
    if (!s.available)
        return "Service not running";
    if (s.Connected)
        return s.AudioSource === "other" ? "Other device" : "Connected";
    const n = nearby(s);
    return n && n.Host !== "none" ? "Other device" : "Disconnected";
}

function headphones(s) {
    if (s.Connected)
        return !!s.IsHeadphones;
    return !!nearby(s)?.Headphones;
}

// AirPods Max report one battery, in whichever slot it comes when seen nearby
function batteries(s) {
    const n = nearby(s);
    const pod = (level, charging) => ({
            "level": typeof level === "number" ? level : -1,
            "charging": !!charging && level >= 0
        });
    let left, right, box;
    if (s.Connected) {
        left = pod(s.BatteryLeft, s.ChargingLeft);
        right = pod(s.BatteryRight, s.ChargingRight);
        box = pod(s.BatteryCase, s.ChargingCase);
    } else if (n) {
        left = pod(n.Left, n.LeftCharging);
        right = pod(n.Right, n.RightCharging);
        box = pod(n.Case, n.CaseCharging);
    } else {
        left = right = box = pod(-1, false);
    }
    if (headphones(s)) {
        const single = left.level >= 0 ? left : right;
        return [Object.assign({
                "key": "headphones",
                "label": s.DeviceModel || "Headphones"
            }, single)];
    }
    return [Object.assign({
            "key": "bud-left",
            "label": "Left"
        }, left), Object.assign({
            "key": "bud-right",
            "label": "Right"
        }, right), Object.assign({
            "key": "case",
            "label": "Case"
        }, box)];
}

function lowest(s) {
    const buds = batteries(s).filter(b => b.key !== "case" && b.level >= 0);
    if (buds.length === 0)
        return null;
    const low = buds.reduce((a, b) => b.level < a.level ? b : a);
    return {
        "level": low.level,
        "charging": buds.some(b => b.charging)
    };
}

// The estimate is only accurate to about 10%: rounded accordingly
function listeningTime(minutes) {
    if (typeof minutes !== "number" || minutes < 0)
        return "";
    if (minutes < 5)
        return "Less than 5 min of listening left";
    if (minutes < 60)
        return "About " + Math.round(minutes / 5) * 5 + " min of listening left";
    const rounded = Math.round(minutes / 10) * 10;
    return "About " + Math.floor(rounded / 60) + "∶" + String(rounded % 60).padStart(2, "0") + " of listening left";
}

function modes(s) {
    if (s.Connected && !s.SupportsANC)
        return [];
    const all = ["off", "anc", "transparency", "adaptive"];
    return s.Connected && !s.SupportsAdaptive ? all.slice(0, 3) : all;
}
