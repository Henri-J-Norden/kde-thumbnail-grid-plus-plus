.pragma library

function keyName(key) {
    if (key === 0) return "—"
    if (key >= Qt.Key_A && key <= Qt.Key_Z)
        return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9)
        return String.fromCharCode(key)
    const special = {
        [Qt.Key_PageUp]: "PgUp", [Qt.Key_PageDown]: "PgDn",
        [Qt.Key_Home]: "Home", [Qt.Key_End]: "End",
        [Qt.Key_Delete]: "Del", [Qt.Key_Space]: "Space",
        [Qt.Key_Insert]: "Ins", [Qt.Key_Return]: "Ret",
        [Qt.Key_Enter]: "Enter", [Qt.Key_Tab]: "Tab",
        [Qt.Key_Backtab]: "BkTab", [Qt.Key_Escape]: "Esc",
        [Qt.Key_Backspace]: "BkSp",
    }
    if (special[key]) return special[key]
    if (key >= Qt.Key_F1 && key <= Qt.Key_F35)
        return "F" + (key - Qt.Key_F1 + 1)
    return "Key_" + key
}
