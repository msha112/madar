// Madar — lock screen
// Lock:  Super + L   ·   quickshell ipc call lock lock
// Test:  quickshell ipc call lock test   (unlocks by itself after 30 s)
// Location: ~/.config/quickshell/LockScreen.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    property bool locked: false
    property bool busy: false
    property bool testMode: false
    property string error: ""
    property string pending: ""
    signal clearInputs()
    signal wrong()

    function lock(test) {
        error = "";
        testMode = !!test;
        locked = true;
        if (testMode) safety.restart();
    }
    function unlock() {
        locked = false;
        busy = false;
        error = "";
        pending = "";
        clearInputs();
    }
    function submit(text) {
        if (busy || text === "") return;
        pending = text;
        busy = true;
        error = "";
        pam.start();
    }

    // Safety net for the first tries: test mode always unlocks after 30 s
    Timer {
        id: safety
        interval: 30000
        onTriggered: if (root.testMode && root.locked) root.unlock()
    }

    PamContext {
        id: pam
        configDirectory: "pam"
        config: "password.conf"

        onPamMessage: {
            if (this.responseRequired) this.respond(root.pending);
        }
        onCompleted: result => {
            root.busy = false;
            root.pending = "";
            if (result === PamResult.Success) {
                root.unlock();
            } else {
                root.error = "Wrong password, try again";
                root.clearInputs();
                root.wrong();
            }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    WlSessionLock {
        locked: root.locked

        WlSessionLockSurface {
            id: surface
            color: Theme.bg

            // Orbits, same as the wallpaper
            Repeater {
                model: [300, 520, 760, 1020]
                Rectangle {
                    required property int modelData
                    required property int index
                    width: modelData * 2; height: width; radius: modelData
                    x: surface.width - 200 - modelData
                    y: surface.height - 80 - modelData
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.orbits[index]
                }
            }

            ColumnLayout {
                id: center
                anchors.centerIn: parent
                spacing: 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        const h = clock.date.getHours();
                        return (h % 12 || 12) + ":" + String(clock.date.getMinutes()).padStart(2, "0");
                    }
                    font.family: Theme.font
                    font.pixelSize: 128
                    font.weight: Font.Light
                    font.letterSpacing: -4
                    color: Theme.text
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDate(clock.date, "dddd, MMMM d")
                    font.family: Theme.font
                    font.pixelSize: 18
                    color: Theme.sub
                }

                Item { implicitHeight: 64 }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 72; implicitHeight: 72; radius: 36
                    color: Theme.accentSoft
                    border.color: Theme.accentLine
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: (Quickshell.env("USER") || "?").charAt(0).toUpperCase()
                        font.family: Theme.font
                        font.pixelSize: 28
                        font.weight: Font.Bold
                        color: Theme.accent
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 12
                    text: Quickshell.env("USER") || ""
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: Theme.text
                }

                // Password field
                Rectangle {
                    id: field
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 20
                    implicitWidth: 340
                    implicitHeight: 54
                    radius: 27
                    color: Theme.card
                    border.width: 1
                    border.color: root.error !== "" ? Theme.danger
                                : (input.activeFocus ? Theme.accentLine : Theme.panelLine)

                    property real shake: 0
                    transform: Translate { x: field.shake }
                    SequentialAnimation {
                        id: shakeAnim
                        NumberAnimation { target: field; property: "shake"; to: -12; duration: 50 }
                        NumberAnimation { target: field; property: "shake"; to: 12; duration: 70 }
                        NumberAnimation { target: field; property: "shake"; to: -8; duration: 60 }
                        NumberAnimation { target: field; property: "shake"; to: 0; duration: 60 }
                    }

                    TextInput {
                        id: input
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        anchors.rightMargin: 60
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.letterSpacing: 2
                        color: Theme.text
                        enabled: !root.busy
                        focus: true
                        clip: true

                        onAccepted: root.submit(text)
                        Keys.onEscapePressed: text = ""

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: input.text === ""
                            text: root.busy ? "Checking…" : "Password"
                            font.family: Theme.font
                            font.pixelSize: 16
                            color: Theme.faint
                        }

                        Component.onCompleted: forceActiveFocus()
                    }

                    // Enter button
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 40; radius: 20
                        color: input.text !== "" ? Theme.accent : Theme.raised
                        Behavior on color { ColorAnimation { duration: 150 } }

                        // arrow
                        Rectangle { anchors.centerIn: parent; width: 14; height: 2; radius: 1; color: input.text !== "" ? Theme.accentInk : Theme.sub }
                        Rectangle { x: 20; y: 15; width: 7; height: 2; radius: 1; rotation: 45; color: input.text !== "" ? Theme.accentInk : Theme.sub }
                        Rectangle { x: 20; y: 23; width: 7; height: 2; radius: 1; rotation: -45; color: input.text !== "" ? Theme.accentInk : Theme.sub }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submit(input.text)
                        }
                    }

                    Connections {
                        target: root
                        function onClearInputs() { input.text = ""; input.forceActiveFocus() }
                        function onWrong() { shakeAnim.restart() }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 12
                    text: root.error !== "" ? root.error
                        : (root.testMode ? "Test mode — unlocks by itself in 30 s" : " ")
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: root.error !== "" ? Theme.danger : Theme.sub
                }
            }

            // Bottom hints
            RowLayout {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 36
                spacing: 24

                Text {
                    readonly property var dev: UPower.displayDevice
                    readonly property real pct: { const p = dev ? dev.percentage : 0; return p > 1 ? p / 100 : p; }
                    text: "Battery " + Math.round(pct * 100) + "%"
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.sub
                }
                Text {
                    text: "Alt + Shift  switches keyboard"
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.sub
                }
            }
        }
    }
}
