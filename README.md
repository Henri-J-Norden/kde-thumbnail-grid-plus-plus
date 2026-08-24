# Thumbnail Grid ++

## Extra features

Compared to the stock Thumbnail Grid switcher:

1. **Highly customizable** - click the Settings button or press `F2` while the task switcher is open.
	- Settings window stays open when task switcher is closed.
	- Also configurable from the Task Switcher preview, but restarting kwin is required to apply the changes.

2. **Hover selection** - show the window just by moving the mouse over it.
	- Requires system Task Switcher setting to be enabled: Visualization → Show selected window. 

3. **Configurable per-window buttons/indicators** on the thumbnails: close, kill, maximize (full / horizontal / vertical), minimize, fullscreen, hide titlebar, pin to all desktops, keep above/below, hide from screenshots, demand attention, shade, transparency, skip taskbar/switcher/pager, debug info window, X11/Wayland protocol badge.
	- **Close/kill** - holding for a configurable grace period escalates to killing the process.
	- Keyboard shortcuts for all actions (which work even if the button is hidden).

4. **Copy menu** (`Space`) - copy the window's UUID, PID, executable path, cmdline, caption, CWD, cgroup scope, parent process, desktop file, platform (X11/Wayland), geometry, output, desktops, activities, state flags, or a ready-made KWin window rule.
	- Mnemonic keyboard shortcuts for all entries.

5. **Window geometry editor (`E`)** - edit x/y/width/height/opacity of the selected window in place.
	- Stays open when task switcher is closed.

6. **htop on the window's process** (`H`), launched in your configured terminal.

7. **Fixes for ultrawide (e.g. 32:9) screens**
	- **Configurable thumbnail height** - the stock Thumbnail Grid produces extremely short and wide thumbnails due to setting the thumbnail height based on the screen aspect ratio.
	- **Max grid aspect ratio** - prevent the task switcher from getting too wide.

8. **Custom styling for minimized windows** to make them easily distinguishable.

9. **Stable grid width/Y-position** - by default, the grid column count and position is latched while the switcher is open, to prevent windows opening or closing from shifting the grid under the cursor.


## Customization

![Settings](docs/settings.png)

Settings can be reached three ways:

1. **From the switcher itself** — press <kbd>F2</kbd> or click the settings button in the bottom-left corner while Alt+Tab (or whichever shortcut you use) is open. Changes apply immediately.
2. **From System Settings → Window Management → Task Switcher**, via the switcher's preview button. Changes made here only take effect after KWin is restarted — log out and back in, or run `kwin_wayland --replace` / `kwin_x11 --replace`.
3. **By editing `~/.config/kwin_thumbnail_grid_pp.ini`** directly. The `[Main]` section holds the main switcher's profile and the `[Alt]` section holds the alternative one. Same caveat: KWin must be restarted for the changes to apply.

## Keyboard shortcuts

Available while the switcher is open, acting on the selected window.

### Navigation

| Key | Action |
| --- | --- |
| <kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd> | Move the selection (wraps around) |

### Window actions

| Key | Action |
| --- | --- |
| <kbd>Delete</kbd> | Close window — hold to kill the process |
| <kbd>PgUp</kbd> | Maximize / restore |
| <kbd>Home</kbd> | Maximize vertically |
| <kbd>End</kbd> | Maximize horizontally |
| <kbd>PgDn</kbd> | Minimize / restore |
| <kbd>F</kbd> | Fullscreen |
| <kbd>T</kbd> | Hide titlebar & frame |
| <kbd>D</kbd> | Pin to all desktops |
| <kbd>A</kbd> | Keep above |
| <kbd>B</kbd> | Keep below |
| <kbd>S</kbd> | Shade |
| <kbd>O</kbd> | Toggle transparency |
| <kbd>I</kbd> | Hide from screenshots & recordings |
| <kbd>N</kbd> | Demand attention |
| <kbd>1</kbd> | Skip taskbar |
| <kbd>2</kbd> | Skip switcher |
| <kbd>3</kbd> | Skip pager |
| <kbd>E</kbd> | Open the geometry editor (<kbd>E</kbd> again or <kbd>Esc</kbd> closes it) |

### Info & tools

| Key | Action |
| --- | --- |
| <kbd>Space</kbd> | Open the copy menu (<kbd>Space</kbd> or <kbd>Esc</kbd> closes it) |
| <kbd>P</kbd> | Copy the window's PID |
| <kbd>H</kbd> | Open htop on the window's process |
| <kbd>F12</kbd> | Show window debug info |
| <kbd>F2</kbd> | Toggle the settings panel |

### Inside the copy menu

| Key | Action |
| --- | --- |
| <kbd>↑</kbd> <kbd>↓</kbd> | Move between entries |
| <kbd>Enter</kbd> | Copy the highlighted entry |
| Underlined letter | Jump to and copy that entry directly |
| <kbd>←</kbd> <kbd>→</kbd> <kbd>Tab</kbd> | Move the grid selection; the menu follows |
| <kbd>Space</kbd> / <kbd>Esc</kbd> | Close the menu |


## Limitations (TODO)
- Keyboard shortcuts cannot be customized or disabled.
- There is no central help overlay (e.g. with `F1`) for listing all keyboard shortcuts.
- The Settings and Edit windows are kwin internal windows, which means they are always on top and do not show up in the taskbar or task switcher.
    - This does not apply to the Debug window, which uses `kdialog` as a workaround.

## Credits

Initially based on [Thumbnail Grid Fix ("Fast Thumbnails")](https://github.com/era-walk/kde-thumbnail-grid-fix), which is itself a reimplementation of KDE's stock [**Thumbnail Grid** task switcher](https://invent.kde.org/plasma/kwin/-/blob/master/src/tabbox/switchers/thumbnail_grid/contents/ui/main.qml).
