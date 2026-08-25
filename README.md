# Keyboard Layout Manager

`io.github.peterszarvas94.keyboard-layout-manager` is an Omarchy bar widget for managing Hyprland
keyboard layouts. It uses the same panel and control language as the Omarchy
plugin manager.

The panel can switch configured layouts, remove them, and search the `xkbcli`
catalog to add new layouts. Changes are written to `~/.config/hypr/input.lua`
and Hyprland is reloaded without root access.

The selected layout is persisted in `~/.local/state/omarchy/keyboard-layout-manager/`
and restored after the shell starts or unlocks. Lock state is checked only in
response to Hyprland layout/layer events; the plugin does not poll continuously.

Validate with:

```sh
omarchy plugin validate .
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" SettingsWidget.qml Panel.qml
```
