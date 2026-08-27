# Thumbnail Grid ++

## Extra features

Compared to the stock Thumbnail Grid switcher:

1. **Highly customizable** - click the Settings button or press `F2` while the task switcher is open.
	- Settings window stays open when task switcher is closed.
	- Also configurable from the Task Switcher preview, but restarting kwin is required to apply the changes.

2. **Hover selection** - show the window just by moving the mouse over it.
	- Requires system Task Switcher setting to be enabled: Visualization → Show selected window. 

3. **Configurable per-window buttons/indicators** on the thumbnails: close, kill, maximize (full / horizontal / vertical), minimize, fullscreen, hide titlebar, pin to all desktops, keep above/below, hide from screenshots, demand attention, shade, transparency, skip taskbar/switcher/pager, debug info window (runs the last custom command), X11/Wayland protocol badge.
	- **Close/kill** - holding for a configurable grace period escalates to killing the process.
	- Keyboard shortcuts for all actions (which work even if the button is hidden).

4. **Copy menu** (`Space`) - copy the window's UUID, PID, executable path, cmdline, caption, CWD, cgroup scope, parent process, desktop file, platform (X11/Wayland), geometry, output, desktops, activities, state flags, or a ready-made KWin window rule.
	- Mnemonic keyboard shortcuts for all entries.

5. **Window geometry editor (`E`)** - edit x/y/width/height/opacity of the selected window in place.
	- Stays open when task switcher is closed.

6. **20 custom commands** (`0`...`9`, `F3`...`F12`) - configurable shell commands run against the selected window.
	- Placeholders written as `{{ expression }}` are evaluated as JavaScript with the window in scope as `w`, and substituted **shell-quoted**: `{{ w.pid }}`, `{{ w.caption }}`, `{{ w.resourceClass }}`, `{{ w.frameGeometry.width }}`, `{{ w.minimized ? "min" : "vis" }}`.
	- The **Placeholders** setting defines extra names as the body of a JSON object (the surrounding `{}` are implied), e.g. `"term": "konsole"` lets a command say `{{ term }} -e htop -p {{! w.pid }}`. They are the only names a placeholder can use without a prefix.
	- `{{! expression }}` substitutes the value **verbatim**, for when it is meant to be shell syntax rather than a single word.
	- A placeholder whose expression throws expands to nothing; an empty command disables the slot.
	- To see which properties a window has, use `{{ dumpProperties(w) }}` - it lists them all with their current values. `dumpProperties(obj, skipFunctions, indent)` works on any object.
	- `1` defaults to `{{!term}} btop -p 1 -f '!^{{!w.pid}}$'`, and `F12` to the window debug info dump - which is also what the per-window **debug info** button runs.

7. **Fixes for ultrawide (e.g. 32:9) screens**
	- **Configurable thumbnail height** - the stock Thumbnail Grid produces extremely short and wide thumbnails due to setting the thumbnail height based on the screen aspect ratio.
	- **Max grid aspect ratio** - prevent the task switcher from getting too wide.

8. **Custom styling for minimized windows** to make them easily distinguishable.

9. **Stable grid width/Y-position** - by default, the grid column count and position is latched while the switcher is open, to prevent windows opening or closing from shifting the grid under the cursor.


## Customization

![Settings](docs/settings.png)

Settings can be reached three ways:

1. **From the switcher itself** (recommended) — press <kbd>F2</kbd> or click the settings button in the bottom-left corner while Alt+Tab (or whichever shortcut you use) is open. Changes apply immediately.
2. **From System Settings → Window Management → Task Switcher**, via the switcher's preview button. Changes made here only take effect after KWin is restarted — log out and back in, or run `kwin_wayland --replace` / `kwin_x11 --replace`.
	- NB: Not all changes are visible due to the way the preview is implemented by kwin.
3. **By editing `~/.config/kwin_thumbnail_grid_pp.ini`** directly. The `[Main]` section holds the main switcher's profile and the `[Alt]` section holds the alternative one. Same caveat: KWin must be restarted for the changes to apply.


## Keyboard shortcuts

Press <kbd>F1</kbd> while the switcher is open to see an in-app cheat sheet of all available shortcuts. All shortcuts can be customized from the settings panel.


## Limitations (TODO)
- The Settings and Edit windows are kwin internal windows, which means they are always on top and do not show up in the taskbar or task switcher.
	- This does not apply to the Debug window, which uses `kdialog` as a workaround.
- Window buttons cannot be reordered.


## Credits

Initially based on [Thumbnail Grid Fix ("Fast Thumbnails")](https://github.com/era-walk/kde-thumbnail-grid-fix), which is itself a reimplementation of KDE's stock [**Thumbnail Grid** task switcher](https://invent.kde.org/plasma/kwin/-/blob/master/src/tabbox/switchers/thumbnail_grid/contents/ui/main.qml).
