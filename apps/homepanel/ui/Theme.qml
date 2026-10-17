pragma Singleton
import QtQuick

// Design tokens. Layout and color ideas only; no third-party artwork.
QtObject {
    readonly property color bgTop: "#1c2030"
    readonly property color bgBottom: "#0c0e14"
    readonly property color tile: "#262b3a"
    readonly property color tilePressed: "#323849"
    readonly property color tileOn: "#f2c660"
    readonly property color textPrimary: "#f4f5f8"
    readonly property color textSecondary: "#9aa1b5"
    readonly property color textOnTile: "#1b1d26"
    readonly property color accent: "#6ea8ff"
    readonly property color danger: "#ff6b6b"

    readonly property int radius: 28
    readonly property int gap: 16
    readonly property int margin: 28

    readonly property int fastMs: 140
    readonly property int baseMs: 260

    readonly property string fontFamily: "sans-serif"
    readonly property var personTints: ["#6ea8ff", "#ff8fb1", "#7ee0b0", "#f2c660"]
}
