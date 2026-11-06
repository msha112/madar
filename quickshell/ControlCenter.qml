// Madar — control center
//   toggles · Wi-Fi list · Bluetooth devices · sound devices · power mode · night light
//   sliders · notifications
// Opens next to the side rail: Super + N, or the controls button on the rail.
// Location: ~/.config/quickshell/ControlCenter.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

PanelWindow {
    id: cc

    required property var notifs

    property bool shown: false
    property real closedAt: 0
    property string page: ""          // "" | "wifi" | "bt" | "audio"

    // Restart / Shut down need a second click within 3 s
    property string armedPower: ""
    Timer { id: disarmPower; interval: 3000; onTriggered: cc.armedPower = "" }

    // ignore a re-open from the same click that just closed it (click outside → on the rail button)
    function toggle() { if (shown) close(); else if (Date.now() - closedAt > 300) open() }
    function open()  { page = ""; shown = true; refresh() }
    function close() { shown = false; closedAt = Date.now(); btScan.running = false; armedPower = "" }
    function openPage(p) {
        page = p;
        if (p === "wifi") { wifiList.running = true; wifiRescan.running = true }
        if (p === "bt") { btList.running = true }
    }

    visible: shown
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "madar-controlcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; top: true; bottom: true }
    margins { left: Theme.gap * 2 + Theme.railWidth; top: Theme.gap; bottom: Theme.gap }
    implicitWidth: 400
    color: "transparent"

    HyprlandFocusGrab {
        windows: [cc]
        active: cc.visible
        onCleared: cc.close()
    }

    Process { id: runner }
    function sh(cmd, a, b) {
        runner.command = ["sh", "-c", cmd, "sh", a ?? "", b ?? ""];
        runner.running = true;
    }

    // ════════════════════════════════════════════════════════
    //  Wi-Fi
    // ════════════════════════════════════════════════════════
    property bool wifiOn: false
    property string wifiName: ""
    property var networks: []          // { ssid, signal, secure, inUse, saved }
    property string wifiPending: ""     // network asking for a password
    property string wifiStatus: ""

    Process {
        id: wifiState
        command: ["sh", "-c", "nmcli -t -f WIFI g; nmcli -t -f NAME,TYPE con show --active | grep ':802-11-wireless$' | head -1 | sed 's/:802-11-wireless$//'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = this.text.split("\n");
                cc.wifiOn = (l[0] || "").trim() === "enabled";
                cc.wifiName = (l[1] || "").trim();
            }
        }
    }

    // nmcli -t escapes ":" inside values as "\:"
    function splitTerse(line) {
        const out = []; let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    Process {
        id: wifiList
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE con show | grep ':802-11-wireless$' | sed 's/:802-11-wireless$//' | sed 's/^/S:/'; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const saved = new Set();
                const byName = {};
                for (const line of this.text.split("\n")) {
                    if (line === "") continue;
                    if (line.startsWith("S:")) { saved.add(line.slice(2).replace(/\\:/g, ":")); continue; }
                    const f = cc.splitTerse(line);
                    const ssid = f[1];
                    if (!ssid) continue;
                    const n = { ssid: ssid, signal: parseInt(f[2]) || 0, secure: (f[3] || "") !== "" && f[3] !== "--", inUse: f[0] === "*" };
                    const old = byName[ssid];
                    if (!old || n.inUse || (!old.inUse && n.signal > old.signal)) byName[ssid] = n;
                }
                const list = Object.values(byName);
                for (const n of list) n.saved = saved.has(n.ssid);
                list.sort((a, b) => (b.inUse - a.inUse) || (b.saved - a.saved) || (b.signal - a.signal));
                cc.networks = list;
            }
        }
    }
    Process {
        id: wifiRescan
        command: ["nmcli", "dev", "wifi", "rescan"]
        onExited: wifiAfterScan.restart()
    }
    Timer { id: wifiAfterScan; interval: 2500; onTriggered: wifiList.running = true }

    Process {
        id: wifiConnect
        property string target: ""
        stderr: StdioCollector { id: wifiErr }
        onExited: code => {
            if (code === 0) { cc.wifiStatus = "Connected to " + target; cc.wifiPending = "" }
            else {
                const e = wifiErr.text.toLowerCase();
                cc.wifiStatus = e.includes("secret") || e.includes("password") || e.includes("802-1x")
                    ? "Wrong password — try again" : "Couldn't connect to " + target;
            }
            cc.refresh();
            wifiList.running = true;
        }
    }
    function connectNetwork(n, password) {
        wifiStatus = "Connecting to " + n.ssid + "…";
        wifiConnect.target = n.ssid;
        if (n.saved && password === undefined)
            wifiConnect.command = ["nmcli", "con", "up", "id", n.ssid];
        else if (password !== undefined)
            wifiConnect.command = ["nmcli", "dev", "wifi", "connect", n.ssid, "password", password];
        else
            wifiConnect.command = ["nmcli", "dev", "wifi", "connect", n.ssid];
        wifiConnect.running = true;
    }
    function clickNetwork(n) {
        if (n.inUse) { sh('nmcli con down id "$1"', n.ssid); wifiStatus = "Disconnected"; later.restart(); return; }
        if (n.saved || !n.secure) { wifiPending = ""; connectNetwork(n); return; }
        wifiPending = wifiPending === n.ssid ? "" : n.ssid;
        wifiStatus = "";
    }

    // ════════════════════════════════════════════════════════
    //  Bluetooth (bluetoothctl)
    // ════════════════════════════════════════════════════════
    property bool btOn: false
    property var btDevices: []          // { mac, name, connected, paired, icon }
    property string btStatus: ""

    Process {
        id: btState
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: cc.btOn = this.text.trim() === "on" }
    }
    Process {
        id: btList
        command: ["bash", "-c", `
            bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
                info="$(bluetoothctl info "$mac" 2>/dev/null)"
                c=0; p=0
                grep -q "Connected: yes" <<<"$info" && c=1
                grep -q "Paired: yes" <<<"$info" && p=1
                icon="$(sed -n 's/^\\s*Icon: //p' <<<"$info")"
                printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$mac" "$c" "$p" "$icon" "$name"
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of this.text.split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 5) continue;
                    // hide nameless devices that only show their address
                    if (!f[4] || f[4].replace(/-/g, ":") === f[0]) continue;
                    out.push({ mac: f[0], connected: f[1] === "1", paired: f[2] === "1", icon: f[3], name: f[4] });
                }
                out.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name));
                cc.btDevices = out;
            }
        }
    }
    Process {
        id: btScan
        command: ["bluetoothctl", "--timeout", "15", "scan", "on"]
        onExited: btList.running = true
    }
    Timer {
        interval: 2000
        repeat: true
        running: btScan.running && cc.page === "bt"
        onTriggered: btList.running = true
    }
    Process {
        id: btAction
        property string label: ""
        onExited: code => {
            cc.btStatus = code === 0 ? "" : "Couldn't " + label;
            btList.running = true;
        }
    }
    function clickDevice(d) {
        if (d.connected) {
            btStatus = "Disconnecting " + d.name + "…";
            btAction.label = "disconnect " + d.name;
            btAction.command = ["bluetoothctl", "disconnect", d.mac];
        } else if (d.paired) {
            btStatus = "Connecting to " + d.name + "…";
            btAction.label = "connect to " + d.name;
            btAction.command = ["bluetoothctl", "connect", d.mac];
        } else {
            btStatus = "Pairing with " + d.name + "…";
            btAction.label = "pair with " + d.name;
            btAction.command = ["sh", "-c", 'bluetoothctl pair "$1" && bluetoothctl trust "$1" && bluetoothctl connect "$1"', "sh", d.mac];
        }
        btAction.running = true;
    }

    // ════════════════════════════════════════════════════════
    //  Sound devices (PipeWire)
    // ════════════════════════════════════════════════════════
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var inputs: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    PwObjectTracker { objects: [cc.sink, cc.source] }
    function nodeName(n) { return n ? (n.description || n.nickname || n.name) : "None" }

    // ════════════════════════════════════════════════════════
    //  Brightness · power mode
    // ════════════════════════════════════════════════════════
    property real brightness: 0.5
    Process {
        id: brightProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split(",");
                if (f.length >= 4) cc.brightness = parseInt(f[3]) / 100;
            }
        }
    }
    property real pendingBrightness: -1
    Timer {
        id: brightApply
        interval: 50
        onTriggered: Hyprland.dispatch("exec brightnessctl -q set " + Math.max(1, Math.round(cc.pendingBrightness * 100)) + "%")
    }

    property string power: ""           // "power-saver" | "balanced" | "performance"
    Process {
        id: powerGet
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector { onStreamFinished: cc.power = this.text.trim() }
    }
    function cyclePower() {
        const order = ["balanced", "performance", "power-saver"];
        const next = order[(order.indexOf(power) + 1) % order.length];
        power = next;
        sh('powerprofilesctl set "$1"', next);
        later.restart();
    }
    readonly property string powerLabel: power === "power-saver" ? "Battery saver"
                                       : power === "performance" ? "Performance"
                                       : power === "balanced" ? "Balanced" : "Unavailable"

    function refresh() {
        wifiState.running = true;
        btState.running = true;
        brightProc.running = true;
        powerGet.running = true;
    }
    Timer { id: later; interval: 1500; onTriggered: cc.refresh() }
    Component.onCompleted: refresh()

    // ════════════════════════════════════════════════════════
    //  Building blocks
    // ════════════════════════════════════════════════════════
    component Toggle: Rectangle {
        id: tg
        property string title: ""
        property string sub: ""
        property bool on: false
        property bool hasMore: false
        signal clicked()
        signal more()

        implicitHeight: 68
        radius: 18
        color: on ? Theme.accent : (tgMouse.containsMouse ? Theme.active : Theme.raised)
        Behavior on color { ColorAnimation { duration: 180 } }

        MouseArea {
            id: tgMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tg.clicked()
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: moreBtn.visible ? moreBtn.left : parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                text: tg.title
                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: tg.on ? Theme.accentInk : Theme.text
            }
            Text {
                Layout.fillWidth: true
                text: tg.sub
                font.family: Theme.font; font.pixelSize: 12
                color: tg.on ? Theme.accentInkSoft : Theme.sub
                elide: Text.ElideRight
            }
        }

        // ›  opens the detail page
        Rectangle {
            id: moreBtn
            visible: tg.hasMore
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 48; radius: 12
            color: moreMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.12) : "transparent"
            Text {
                anchors.centerIn: parent
                text: "›"
                font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold
                color: tg.on ? Theme.accentInk : Theme.sub
            }
            MouseArea {
                id: moreMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tg.more()
            }
        }
    }

    component SliderRow: Item {
        id: sr
        property string label: ""
        property real value: 0
        property string valueText: Math.round(value * 100) + "%"
        signal moved(real v)
        signal labelClicked()

        implicitHeight: 44

        Text {
            id: srLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 78
            text: sr.label
            font.family: Theme.font; font.pixelSize: 13
            color: Theme.sub2
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sr.labelClicked() }
        }
        Item {
            id: track
            anchors.left: srLabel.right
            anchors.right: srValue.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 22

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 8; radius: 4
                color: Theme.track2
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * Math.max(0, Math.min(1, sr.value)); height: 8; radius: 4
                color: Theme.text
            }
            Rectangle {
                x: parent.width * Math.max(0, Math.min(1, sr.value)) - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 10
                color: "#FFFFFF"
                border.color: Theme.panelLine
                scale: dragArea.pressed ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
            }
            MouseArea {
                id: dragArea
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                function apply(mx) { sr.moved(Math.max(0, Math.min(1, (mx - 6) / track.width))) }
                onPressed: m => dragArea.apply(m.x)
                onPositionChanged: m => { if (dragArea.pressed) dragArea.apply(m.x) }
                onWheel: w => sr.moved(Math.max(0, Math.min(1, sr.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
            }
        }
        Text {
            id: srValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: sr.valueText
            font.family: Theme.font; font.pixelSize: 12
            color: Theme.sub
        }
    }

    // A row in a detail page list
    component ListRow: Rectangle {
        id: lr
        property string title: ""
        property string sub: ""
        property bool active: false
        property string badge: ""
        signal clicked()

        Layout.fillWidth: true
        implicitHeight: 52
        radius: 14
        color: active ? Theme.accentSoft : (lrMouse.containsMouse ? Theme.hover : "transparent")
        border.width: active ? 1 : 0
        border.color: Theme.accentLine

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: lr.title
                    font.family: Theme.font; font.pixelSize: 14
                    font.weight: lr.active ? Font.DemiBold : Font.Normal
                    color: Theme.text
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: lr.sub !== ""
                    text: lr.sub
                    font.family: Theme.font; font.pixelSize: 11
                    color: Theme.sub
                    elide: Text.ElideRight
                }
            }
            Text {
                visible: lr.badge !== ""
                text: lr.badge
                font.family: Theme.font; font.pixelSize: 11
                color: lr.active ? Theme.accent : Theme.faint
            }
        }
        MouseArea {
            id: lrMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lr.clicked()
        }
    }

    // Wi-Fi signal as 4 little bars
    component Bars: Row {
        id: bars
        property int strength: 0
        spacing: 2
        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.bottom: parent.bottom
                width: 4; height: 5 + index * 3; radius: 1
                color: bars.strength > index * 25 ? Theme.text : Theme.track2
            }
        }
    }

    // Header of a detail page
    component PageHeader: RowLayout {
        id: ph
        property string title: ""
        property string action: ""
        property bool busy: false
        signal actionClicked()
        signal back()

        Layout.fillWidth: true
        spacing: 10
        Rectangle {
            implicitWidth: 36; implicitHeight: 36; radius: 12
            color: backMouse.containsMouse ? Theme.active : Theme.raised
            Text { anchors.centerIn: parent; text: "‹"; font.pixelSize: 22; font.weight: Font.DemiBold; color: Theme.text }
            MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ph.back() }
        }
        Text {
            Layout.fillWidth: true
            text: ph.title
            font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            color: Theme.text
        }
        Rectangle {
            visible: ph.action !== ""
            implicitWidth: actText.implicitWidth + 24; implicitHeight: 32; radius: 11
            color: actMouse.containsMouse ? Theme.active : Theme.raised
            Text {
                id: actText
                anchors.centerIn: parent
                text: ph.busy ? "Searching…" : ph.action
                font.family: Theme.font; font.pixelSize: 12
                color: Theme.text
            }
            MouseArea { id: actMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ph.actionClicked() }
        }
    }

    // ════════════════════════════════════════════════════════
    //  Panel
    // ════════════════════════════════════════════════════════
    Rectangle {
        id: panel
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.cardGlass
        border.color: Theme.panelLine
        border.width: 1
        focus: true
        Keys.onEscapePressed: { if (cc.page !== "") cc.page = ""; else cc.close() }

        property real slide: cc.visible ? 0 : -24
        transform: Translate { x: panel.slide }
        opacity: cc.visible ? 1 : 0
        Behavior on slide { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // ── Header ───────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    implicitWidth: 42; implicitHeight: 42; radius: 21
                    color: Theme.accentSoft
                    border.color: Theme.accentLine
                    Text {
                        anchors.centerIn: parent
                        text: (Quickshell.env("USER") || "?").charAt(0).toUpperCase()
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold
                        color: Theme.accent
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: Quickshell.env("USER") || "User"
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    Text {
                        readonly property var dev: UPower.displayDevice
                        readonly property real pct: { const p = dev ? dev.percentage : 0; return p > 1 ? p / 100 : p; }
                        text: "Battery " + Math.round(pct * 100) + "%" + (dev && dev.state === UPowerDeviceState.Charging ? " · charging" : "")
                        font.family: Theme.font; font.pixelSize: 12
                        color: Theme.sub
                    }
                }
                Rectangle {
                    implicitWidth: setText.implicitWidth + 24; implicitHeight: 34; radius: 12
                    color: setMouse.containsMouse ? Theme.active : Theme.raised
                    Text { id: setText; anchors.centerIn: parent; text: "Settings"; font.family: Theme.font; font.pixelSize: 12; color: Theme.text }
                    MouseArea {
                        id: setMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Hyprland.dispatch("exec gnome-control-center"); cc.close() }
                    }
                }

                // Restart · Shut down  (click twice to confirm)
                Repeater {
                    model: [
                        { id: "reboot",   tip: "Restart",   cmd: "systemctl reboot" },
                        { id: "poweroff", tip: "Shut down", cmd: "systemctl poweroff" }
                    ]
                    Rectangle {
                        id: pwr
                        required property var modelData
                        readonly property bool armed: cc.armedPower === modelData.id
                        implicitWidth: armed ? confirmText.implicitWidth + 24 : 34
                        implicitHeight: 34
                        radius: 12
                        color: armed ? Theme.danger : (pwrMouse.containsMouse ? Theme.active : Theme.raised)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on implicitWidth { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        // restart: circular arrow · shut down: power symbol
                        Shape {
                            visible: !pwr.armed
                            anchors.centerIn: parent
                            width: 18; height: 18
                            layer.enabled: true
                            layer.samples: 4

                            // open circle (gap at the top)
                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: Theme.text
                                strokeWidth: 2
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: 9; centerY: 10; radiusX: 6.5; radiusY: 6.5
                                    startAngle: pwr.modelData.id === "poweroff" ? -55 : -40
                                    sweepAngle: pwr.modelData.id === "poweroff" ? 290 : 300
                                }
                            }
                            // power: bar through the gap · restart: arrow tip
                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: Theme.text
                                strokeWidth: 2
                                capStyle: ShapePath.RoundCap
                                joinStyle: ShapePath.RoundJoin
                                startX: pwr.modelData.id === "poweroff" ? 9 : 11.5
                                startY: pwr.modelData.id === "poweroff" ? 2 : 2.5
                                PathLine {
                                    x: pwr.modelData.id === "poweroff" ? 9 : 14.5
                                    y: pwr.modelData.id === "poweroff" ? 9 : 5.5
                                }
                                PathLine {
                                    x: pwr.modelData.id === "poweroff" ? 9 : 11
                                    y: pwr.modelData.id === "poweroff" ? 9 : 7.5
                                }
                            }
                        }
                        Text {
                            id: confirmText
                            visible: pwr.armed
                            anchors.centerIn: parent
                            text: pwr.modelData.tip + "?"
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                            color: Theme.accentInk
                        }

                        MouseArea {
                            id: pwrMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (pwr.armed) { cc.armedPower = ""; Hyprland.dispatch("exec " + pwr.modelData.cmd); }
                                else { cc.armedPower = pwr.modelData.id; disarmPower.restart(); }
                            }
                        }

                        // tooltip
                        Rectangle {
                            visible: pwrMouse.containsMouse && !pwr.armed
                            anchors.top: parent.bottom
                            anchors.topMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitWidth: tipText.implicitWidth + 16; implicitHeight: 24; radius: 8
                            color: Theme.raised
                            border.color: Theme.panelLine
                            z: 10
                            Text { id: tipText; anchors.centerIn: parent; text: pwr.modelData.tip; font.family: Theme.font; font.pixelSize: 11; color: Theme.text }
                        }
                    }
                }
            }

            // ════════════════════════════════════════════════
            //  Main page
            // ════════════════════════════════════════════════
            ColumnLayout {
                visible: cc.page === ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 10; columnSpacing: 10

                    Toggle {
                        Layout.fillWidth: true
                        title: "Wi-Fi"
                        on: cc.wifiOn
                        hasMore: true
                        sub: !cc.wifiOn ? "Off" : (cc.wifiName || "Not connected")
                        onClicked: {
                            cc.sh('nmcli radio wifi "$1"', cc.wifiOn ? "off" : "on");
                            cc.wifiOn = !cc.wifiOn;
                            later.restart();
                        }
                        onMore: cc.openPage("wifi")
                    }
                    Toggle {
                        Layout.fillWidth: true
                        title: "Bluetooth"
                        on: cc.btOn
                        hasMore: true
                        sub: !cc.btOn ? "Off" : (cc.btDevices.find(d => d.connected)?.name ?? "On")
                        onClicked: {
                            cc.sh('bluetoothctl power "$1"', cc.btOn ? "off" : "on");
                            cc.btOn = !cc.btOn;
                            later.restart();
                        }
                        onMore: cc.openPage("bt")
                    }
                    Toggle {
                        Layout.fillWidth: true
                        title: "Do not disturb"
                        on: cc.notifs.dnd
                        sub: cc.notifs.dnd ? "Popups hidden" : "Off"
                        onClicked: cc.notifs.dnd = !cc.notifs.dnd
                    }
                    Toggle {
                        Layout.fillWidth: true
                        title: "Night light"
                        on: Theme.nightLight !== "off"
                        sub: Theme.nightLight === "off" ? "Off" : (Theme.nightLight === "auto" ? "6 PM – 6 AM" : "On now")
                        onClicked: Theme.cycleNightLight()
                    }
                    Toggle {
                        Layout.fillWidth: true
                        title: "Power"
                        on: cc.power === "power-saver"
                        sub: cc.powerLabel
                        onClicked: cc.cyclePower()
                    }
                    Toggle {
                        Layout.fillWidth: true
                        title: "Appearance"
                        on: Theme.mode !== "auto"
                        sub: Theme.mode === "auto" ? "Auto · " + (Theme.day ? "day" : "night") : (Theme.day ? "Always day" : "Always night")
                        onClicked: Theme.cycleMode()
                    }
                }

                // Accent color
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        Layout.fillWidth: true
                        text: "Accent  ·  " + Theme.current.name
                        font.family: Theme.font; font.pixelSize: 13
                        color: Theme.sub2
                    }
                    Repeater {
                        model: Theme.accentKeys
                        Rectangle {
                            id: swatch
                            required property string modelData
                            readonly property bool picked: Theme.accentName === modelData
                            implicitWidth: 30; implicitHeight: 30; radius: 15
                            color: "transparent"
                            border.width: picked ? 2 : 0
                            border.color: Theme.text
                            Rectangle {
                                anchors.centerIn: parent
                                width: 22; height: 22; radius: 11
                                color: Theme.accents[swatch.modelData].color
                                scale: swMouse.containsMouse ? 1.12 : 1
                                Behavior on scale { NumberAnimation { duration: 120 } }
                            }
                            MouseArea {
                                id: swMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Theme.setAccent(swatch.modelData)
                            }
                        }
                    }
                }

                // Sliders + sound output
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: sliders.implicitHeight + 16
                    radius: 18
                    color: Theme.inset

                    ColumnLayout {
                        id: sliders
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 16 }
                        spacing: 0

                        SliderRow {
                            Layout.fillWidth: true
                            label: "Brightness"
                            value: cc.brightness
                            onMoved: v => {
                                cc.brightness = v;
                                cc.pendingBrightness = v;
                                brightApply.restart();
                            }
                        }
                        SliderRow {
                            Layout.fillWidth: true
                            label: cc.sink?.audio?.muted ? "Muted" : "Volume"
                            value: cc.sink?.audio?.volume ?? 0
                            valueText: cc.sink?.audio?.muted ? "—" : Math.round((cc.sink?.audio?.volume ?? 0) * 100) + "%"
                            onMoved: v => { if (cc.sink?.audio) { cc.sink.audio.muted = false; cc.sink.audio.volume = v } }
                            onLabelClicked: { if (cc.sink?.audio) cc.sink.audio.muted = !cc.sink.audio.muted }
                        }
                        // output device → sound page
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            implicitHeight: 34
                            radius: 10
                            color: outMouse.containsMouse ? Theme.hover : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                Text {
                                    text: "Output"
                                    Layout.preferredWidth: 74
                                    font.family: Theme.font; font.pixelSize: 12
                                    color: Theme.sub
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: cc.nodeName(cc.sink)
                                    font.family: Theme.font; font.pixelSize: 12
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }
                                Text { text: "›"; font.pixelSize: 18; color: Theme.sub }
                            }
                            MouseArea { id: outMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cc.openPage("audio") }
                        }
                    }
                }

                // Notifications
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Text {
                        Layout.fillWidth: true
                        text: "Notifications" + (cc.notifs.count > 0 ? "  " + cc.notifs.count : "")
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    Text {
                        visible: cc.notifs.count > 0
                        text: "Clear all"
                        font.family: Theme.font; font.pixelSize: 12
                        color: Theme.sub
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cc.notifs.clearAll() }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    model: cc.notifs.model
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: NotificationCard {
                        required property var modelData
                        width: ListView.view.width
                        notif: modelData
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cc.notifs.count === 0
                        text: "You're all caught up"
                        font.family: Theme.font; font.pixelSize: 13
                        color: Theme.faint
                    }
                }
            }

            // ════════════════════════════════════════════════
            //  Wi-Fi page
            // ════════════════════════════════════════════════
            ColumnLayout {
                visible: cc.page === "wifi"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                PageHeader {
                    onBack: cc.page = ""
                    title: "Wi-Fi"
                    action: "Refresh"
                    busy: wifiRescan.running || wifiAfterScan.running
                    onActionClicked: wifiRescan.running = true
                }

                Text {
                    visible: !cc.wifiOn
                    Layout.fillWidth: true
                    text: "Wi-Fi is off. Turn it on from the main page."
                    font.family: Theme.font; font.pixelSize: 13
                    color: Theme.sub
                    wrapMode: Text.Wrap
                }
                Text {
                    visible: cc.wifiStatus !== ""
                    Layout.fillWidth: true
                    text: cc.wifiStatus
                    font.family: Theme.font; font.pixelSize: 12
                    color: cc.wifiStatus.startsWith("Wrong") || cc.wifiStatus.startsWith("Couldn't") ? Theme.danger : Theme.sub
                    wrapMode: Text.Wrap
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: cc.wifiOn ? cc.networks : []
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: ColumnLayout {
                        id: net
                        required property var modelData
                        width: ListView.view.width
                        spacing: 6

                        ListRow {
                            title: net.modelData.ssid
                            sub: net.modelData.inUse ? "Connected · click to disconnect"
                               : net.modelData.saved ? "Saved" : (net.modelData.secure ? "Secured" : "Open")
                            active: net.modelData.inUse
                            onClicked: cc.clickNetwork(net.modelData)

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Bars { strength: net.modelData.signal; anchors.verticalCenter: parent.verticalCenter; height: 14 }
                            }
                        }

                        // password field for a new secured network
                        Rectangle {
                            visible: cc.wifiPending === net.modelData.ssid
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: 14
                            color: Theme.field
                            border.color: pw.activeFocus ? Theme.accentLine : Theme.panelLine

                            onVisibleChanged: if (visible) { pw.text = ""; pw.forceActiveFocus() }

                            TextInput {
                                id: pw
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 90
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                font.family: Theme.font; font.pixelSize: 14
                                color: Theme.text
                                clip: true
                                onAccepted: if (text !== "") cc.connectNetwork(net.modelData, text)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pw.text === ""
                                    text: "Password"
                                    font: pw.font
                                    color: Theme.faint
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 76; height: 34; radius: 11
                                color: pw.text !== "" ? Theme.accent : Theme.raised
                                Text {
                                    anchors.centerIn: parent
                                    text: "Connect"
                                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                    color: pw.text !== "" ? Theme.accentInk : Theme.sub
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (pw.text !== "") cc.connectNetwork(net.modelData, pw.text)
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cc.wifiOn && cc.networks.length === 0
                        text: "Looking for networks…"
                        font.family: Theme.font; font.pixelSize: 13
                        color: Theme.faint
                    }
                }
            }

            // ════════════════════════════════════════════════
            //  Bluetooth page
            // ════════════════════════════════════════════════
            ColumnLayout {
                visible: cc.page === "bt"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                PageHeader {
                    onBack: cc.page = ""
                    title: "Bluetooth"
                    action: cc.btOn ? "Find devices" : ""
                    busy: btScan.running
                    onActionClicked: if (!btScan.running) btScan.running = true
                }

                Text {
                    visible: !cc.btOn
                    Layout.fillWidth: true
                    text: "Bluetooth is off. Turn it on from the main page."
                    font.family: Theme.font; font.pixelSize: 13
                    color: Theme.sub
                    wrapMode: Text.Wrap
                }
                Text {
                    visible: cc.btStatus !== ""
                    Layout.fillWidth: true
                    text: cc.btStatus
                    font.family: Theme.font; font.pixelSize: 12
                    color: cc.btStatus.startsWith("Couldn't") ? Theme.danger : Theme.sub
                    wrapMode: Text.Wrap
                }
                Text {
                    visible: cc.btOn && btScan.running
                    Layout.fillWidth: true
                    text: "Put your device in pairing mode — it will show up below."
                    font.family: Theme.font; font.pixelSize: 12
                    color: Theme.sub
                    wrapMode: Text.Wrap
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: cc.btOn ? cc.btDevices : []
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: dev
                        required property var modelData
                        width: ListView.view.width
                        height: 56
                        ListRow {
                            anchors.fill: parent
                            title: dev.modelData.name
                            sub: dev.modelData.connected ? "Connected · click to disconnect"
                               : dev.modelData.paired ? "Paired · click to connect" : "New · click to pair"
                            active: dev.modelData.connected
                            badge: dev.modelData.icon.replace("audio-headset", "headset").replace("audio-headphones", "headphones")
                                                      .replace("input-", "").replace("audio-card", "speaker")
                            onClicked: cc.clickDevice(dev.modelData)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cc.btOn && cc.btDevices.length === 0
                        text: "No devices yet — press “Find devices”"
                        font.family: Theme.font; font.pixelSize: 13
                        color: Theme.faint
                    }
                }
            }

            // ════════════════════════════════════════════════
            //  Sound page
            // ════════════════════════════════════════════════
            ColumnLayout {
                visible: cc.page === "audio"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                PageHeader { title: "Sound"; onBack: cc.page = "" }

                Text {
                    Layout.topMargin: 4
                    text: "Output"
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: Theme.sub
                }
                Repeater {
                    model: cc.outputs
                    ListRow {
                        required property var modelData
                        title: cc.nodeName(modelData)
                        active: cc.sink === modelData
                        badge: active ? "In use" : ""
                        onClicked: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }

                Text {
                    Layout.topMargin: 10
                    text: "Microphone"
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: Theme.sub
                }
                Repeater {
                    model: cc.inputs
                    ListRow {
                        required property var modelData
                        title: cc.nodeName(modelData)
                        active: cc.source === modelData
                        badge: active ? "In use" : ""
                        onClicked: Pipewire.preferredDefaultAudioSource = modelData
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
