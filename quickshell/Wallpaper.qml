// Madar — background ("orbits")
// Location: ~/.config/quickshell/Wallpaper.qml
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

PanelWindow {
    id: wall

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "madar-wallpaper"
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        Behavior on color { ColorAnimation { duration: Theme.themeAnim } }
    }

    // Center of the orbits: bottom-right corner area
    readonly property real cx: width - 200
    readonly property real cy: height - 80
    // Where the accent "planet" sits on the middle orbit
    readonly property real angle: -147 * Math.PI / 180

    component Orbit: ShapePath {
        id: orbit
        property real r: 300
        property real ocx: 0
        property real ocy: 0
        fillColor: "transparent"
        strokeWidth: 2
        PathAngleArc {
            centerX: orbit.ocx; centerY: orbit.ocy
            radiusX: orbit.r; radiusY: orbit.r
            startAngle: 0; sweepAngle: 360
        }
    }

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        Orbit { r: 300;  ocx: wall.cx; ocy: wall.cy; strokeColor: Theme.orbits[0] }
        Orbit { r: 520;  ocx: wall.cx; ocy: wall.cy; strokeColor: Theme.orbits[1] }
        Orbit { r: 760;  ocx: wall.cx; ocy: wall.cy; strokeColor: Theme.orbits[2] }
        Orbit { r: 1020; ocx: wall.cx; ocy: wall.cy; strokeColor: Theme.orbits[3] }
    }

    // Soft halo + planet
    Rectangle {
        width: 64; height: 64; radius: 32
        x: wall.cx + 520 * Math.cos(wall.angle) - width / 2
        y: wall.cy + 520 * Math.sin(wall.angle) - height / 2
        color: Theme.accent
        opacity: Theme.day ? 0.18 : 0.08
    }
    Rectangle {
        width: 20; height: 20; radius: 10
        x: wall.cx + 520 * Math.cos(wall.angle) - width / 2
        y: wall.cy + 520 * Math.sin(wall.angle) - height / 2
        color: Theme.accent
    }
}
