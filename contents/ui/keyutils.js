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

// --- Typing into KWin's internal windows -------------------------------------
//
// See KwinTextField for why this is needed: KWin synthesises key events with an
// empty text(), so Qt's text controls insert nothing. Shared by KwinTextField
// and KwinTextArea.

const shiftedAscii = {
    "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
    "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
    "-": "_", "=": "+", "[": "{", "]": "}", "\\": "|",
    ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "`": "~"
}

// "" when the key carries no printable character of its own (modifiers held,
// function keys, navigation keys - all of which the text control handles by key
// code). `multiline` maps Return/Enter onto a newline, for text areas.
function charForKey(key, modifiers, multiline) {
    if (modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
        return ""
    if (multiline && (key === Qt.Key_Return || key === Qt.Key_Enter))
        return "\n"
    // Qt's key codes for printable ASCII are the unshifted character, with
    // letters as uppercase.
    if (key < 0x20 || key > 0x7e)
        return ""
    const base = String.fromCharCode(key)
    const isLetter = key >= Qt.Key_A && key <= Qt.Key_Z
    if (modifiers & Qt.ShiftModifier)
        return isLetter ? base : (shiftedAscii[base] !== undefined ? shiftedAscii[base] : base)
    return isLetter ? base.toLowerCase() : base
}

// Inserts the character `event` stands for into `field` by hand. Returns true
// if the event was consumed, i.e. if it should be marked accepted.
function insertKeyEvent(field, event, multiline) {
    if (event.text.length > 0)
        return false  // normal host: let the text control insert it
    if (field.readOnly)
        return false
    const ch = charForKey(event.key, event.modifiers, multiline)
    if (!ch)
        return false
    if (field.selectionStart !== field.selectionEnd)
        field.remove(field.selectionStart, field.selectionEnd)
    if (field.maximumLength !== undefined && field.maximumLength >= 0
            && field.length >= field.maximumLength)
        return true
    field.insert(field.cursorPosition, ch)
    return true
}
