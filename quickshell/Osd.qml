// Madar — on-screen display for volume and brightness
// Location: ~/.config/quickshell/Osd.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    property string kind: "volume"       // "volume" | "brightness"
    property real value: 0
    property bool muted: false
    property bool shown: false

    function show(k, v, m) {
        kind = k;
        value = v;
        muted = !!m;
        shown = true;
        hideTimer.restart();
    }

    Timer { id: hideTimer; interval: 1400; onTriggered: root.shown = false }

    // ── Volume: react to any change of the default output ────
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.sink] }

    // Ignore the burst of changes right after startup
    property bool ready: false
    Timer { interval: 1500; running: true; onTriggered: root.ready = true }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() { if (root.ready) root.show("volume", root.sink.audio.volume, root.sink.audio.muted) }
        function onMutedChanged()  { if (root.ready) root.show("volume", root.sink.audio.volume, root.sink.audio.muted) }
    }

    // ── Brightness: Hyprland key binding calls `quickshell ipc call osd brightness`
    Process {
        id: brightProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split(",");
                if (f.length >= 4) root.show("brightness", parseInt(f[3]) / 100, false);
            }
        }
    }
    IpcHandler {
        target: "osd"
        function brightness(): void { brightProc.running = true }
    }

    // ── The pill ─────────────────────────────────────────────
    PanelWindow {
        visible: root.shown || pill.opacity > 0
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "madar-osd"
        exclusionMode: ExclusionMode.Ignore
        anchors { bottom: true }
        margins { bottom: 48 }
        implicitWidth: 320
        implicitHeight: 64
        color: "transparent"

        Rectangle {
            id: pill
            anchors.fill: parent
            radius: 32
            color: Theme.cardGlass
            border.color: Theme.panelLine
            border.width: 1

            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 14

                // icon: speaker or sun
                Item {
                    implicitWidth: 22; implicitHeight: 22

                    // sun
                    Item {
                        anchors.fill: parent
                        visible: root.kind === "brightness"
                        Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.text }
                        Repeater {
                            model: 8
                            Rectangle {
                                required property int index
                                x: 11 - 1 + Math.cos(index * Math.PI / 4) * 9 - 0
                                y: 11 - 1 + Math.sin(index * Math.PI / 4) * 9
                                width: 2.4; height: 2.4; radius: 1.2
                                color: Theme.text
                            }
                        }
                    }
                    // speaker
                    Item {
                        anchors.fill: parent
                        visible: root.kind === "volume"
                        Rectangle { x: 2; y: 8; width: 5; height: 6; radius: 1; color: Theme.text }
                        Rectangle { x: 5; y: 5; width: 7; height: 12; radius: 2; color: Theme.text }
                        Rectangle {
                            visible: !root.muted
                            x: 13; y: 6; width: 7; height: 10; radius: 5
                            color: "transparent"; border.width: 2; border.color: Theme.text
                        }
                        Rectangle { visible: root.muted; x: 13; y: 10; width: 9; height: 2; radius: 1; rotation: 45; color: Theme.danger }
                        Rectangle { visible: root.muted; x: 13; y: 10; width: 9; height: 2; radius: 1; rotation: -45; color: Theme.danger }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    Rectangle { anchors.fill: parent; radius: 4; color: Theme.track }
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.muted ? 0 : root.value))
                        height: parent.height
                        radius: 4
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                }

                Text {
                    Layout.preferredWidth: 48
                    horizontalAlignment: Text.AlignRight
                    text: root.muted ? "Muted" : Math.round(root.value * 100) + "%"
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: Theme.text
                }
            }
        }
    }
}
