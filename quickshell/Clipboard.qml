// Madar — clipboard history (Super + V)
//   type to filter · ↑ ↓ move · Enter paste · Delete remove · Esc close
// Needs: cliphist (history is recorded by wl-paste --watch, see hyprland.conf)
// Location: ~/.config/quickshell/Clipboard.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: clip

    property bool shown: false
    property int current: 0
    property var items: []            // { id, kind: "txt"|"img", text, path }
    property string targetClass: ""   // window that was active when we opened

    function toggle() { shown ? close() : open() }
    function open() {
        targetClass = Windows.appId(Hyprland.activeToplevel);
        query.text = "";
        current = 0;
        loader.running = true;
        shown = true;
    }
    function close() { shown = false }

    readonly property var shownItems: {
        const q = query.text.trim().toLowerCase();
        if (q === "") return items;
        return items.filter(it => it.kind === "txt" && it.text.toLowerCase().includes(q));
    }

    // ── Read history (images are decoded once into small files) ──
    Process {
        id: loader
        command: ["bash", "-c", `
            dir="$XDG_RUNTIME_DIR/madar-clip"; mkdir -p "$dir"
            cliphist list 2>/dev/null | head -80 | while IFS=$'\\t' read -r id rest; do
                if [[ "$rest" == "[[ binary data"* ]]; then
                    [ -s "$dir/$id.png" ] || cliphist decode "$id" > "$dir/$id.png" 2>/dev/null
                    printf '%s\\timg\\t%s\\n' "$id" "$dir/$id.png"
                else
                    printf '%s\\ttxt\\t%s\\n' "$id" "$rest"
                fi
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of this.text.split("\n")) {
                    const a = line.indexOf("\t");
                    if (a < 0) continue;
                    const b = line.indexOf("\t", a + 1);
                    const id = line.slice(0, a), kind = line.slice(a + 1, b), rest = line.slice(b + 1);
                    out.push(kind === "img" ? { id: id, kind: "img", text: "Image", path: rest }
                                            : { id: id, kind: "txt", text: rest, path: "" });
                }
                clip.items = out;
            }
        }
    }

    Process { id: runner }
    function sh(cmd) { runner.command = ["bash", "-c", cmd]; runner.running = true }

    function paste(i) {
        const it = shownItems[i];
        if (!it) return;
        close();
        // terminals paste with Ctrl+Shift+V
        const term = /kitty|alacritty|foot|wezterm|terminal|konsole|ptyxis/i.test(targetClass);
        const keys = term ? "CTRL SHIFT, V" : "CTRL, V";
        sh(`cliphist decode '${it.id}' | wl-copy && sleep 0.15 && hyprctl dispatch sendshortcut "${keys}, activewindow"`);
    }
    function remove(i) {
        const it = shownItems[i];
        if (!it) return;
        sh(`cliphist list | grep -P '^${it.id}\\t' | cliphist delete`);
        items = items.filter(x => x.id !== it.id);
        current = Math.min(current, shownItems.length - 1);
    }
    function clearAll() {
        sh(`cliphist wipe; rm -rf "$XDG_RUNTIME_DIR/madar-clip"`);
        items = [];
    }

    visible: shown
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "madar-clipboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"

    onVisibleChanged: if (visible) query.forceActiveFocus()

    Rectangle {
        anchors.fill: parent
        color: Theme.backdrop
        MouseArea { anchors.fill: parent; onClicked: clip.close() }
    }

    Rectangle {
        id: card
        width: 600
        height: Math.min(parent.height * 0.75, content.implicitHeight + 24)
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.14
        radius: 24
        color: Theme.cardGlass
        border.color: Theme.panelLine
        border.width: 1

        opacity: clip.visible ? 1 : 0
        scale: clip.visible ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // header + search
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 16
                color: Theme.field
                border.color: Theme.accentLine
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        text: "Clipboard"
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: Theme.accent
                    }
                    TextInput {
                        id: query
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.font
                        font.pixelSize: 15
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentInk
                        clip: true
                        focus: true
                        onTextChanged: clip.current = 0

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: query.text === ""
                            text: "Search…"
                            font: query.font
                            color: Theme.faint
                        }

                        Keys.onPressed: event => {
                            const last = clip.shownItems.length - 1;
                            if (event.key === Qt.Key_Escape) clip.close();
                            else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) clip.current = Math.min(clip.current + 1, last);
                            else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) clip.current = Math.max(clip.current - 1, 0);
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) clip.paste(clip.current);
                            else if (event.key === Qt.Key_Delete) clip.remove(clip.current);
                            else return;
                            event.accepted = true;
                        }
                    }
                    Text {
                        visible: clip.items.length > 0
                        text: "Clear all"
                        font.family: Theme.font; font.pixelSize: 12
                        color: Theme.sub
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: clip.clearAll() }
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: contentHeight
                clip: true
                spacing: 4
                model: clip.shownItems
                currentIndex: clip.current
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === clip.current

                    width: ListView.view.width
                    height: modelData.kind === "img" ? 116 : Math.min(84, txt.implicitHeight + 24)
                    radius: 12
                    color: sel ? Theme.active : (rowMouse.containsMouse ? Theme.hover : "transparent")

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: row.sel ? 22 : 0; radius: 2
                        color: Theme.accent
                        Behavior on height { NumberAnimation { duration: 120 } }
                    }

                    Text {
                        id: txt
                        visible: row.modelData.kind === "txt"
                        anchors.left: parent.left
                        anchors.right: delBtn.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
                        anchors.rightMargin: 8
                        text: row.modelData.text
                        textFormat: Text.PlainText
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.text
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    Image {
                        visible: row.modelData.kind === "img"
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
                        height: 96
                        width: Math.min(400, sourceSize.width * (96 / Math.max(1, sourceSize.height)))
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        source: row.modelData.kind === "img" ? "file://" + row.modelData.path : ""
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: clip.current = row.index
                        onClicked: clip.paste(row.index)
                    }

                    // delete
                    Rectangle {
                        id: delBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28; radius: 14
                        visible: row.sel
                        color: delMouse.containsMouse ? Theme.danger : Theme.raised
                        Rectangle { anchors.centerIn: parent; width: 11; height: 2; radius: 1; rotation: 45; color: Theme.text }
                        Rectangle { anchors.centerIn: parent; width: 11; height: 2; radius: 1; rotation: -45; color: Theme.text }
                        MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: clip.remove(row.index)
                        }
                    }
                }
            }

            Text {
                visible: clip.shownItems.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.bottomMargin: 16
                horizontalAlignment: Text.AlignHCenter
                text: clip.items.length === 0 ? "Nothing copied yet" : "No matches"
                font.family: Theme.font; font.pixelSize: 13
                color: Theme.sub
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: "Enter paste     Delete remove     Esc close"
                font.family: Theme.font; font.pixelSize: 11
                color: Theme.faint
            }
        }
    }
}
