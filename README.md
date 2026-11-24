# ambxst-mod-openlogi-lock-key

An [Ambxst](https://github.com/Axenide/Ambxst) mod that routes
[OpenLogi](https://github.com/AprilNEA/OpenLogi)'s lock key indicator
(Caps / Num / Scroll Lock) into Ambxst's own notification system.

OpenLogi draws that indicator as a real toplevel window (app id
`openlogi-lock-key-osd`). Under Hyprland the window gets tiled and takes half
the workspace. This mod closes it the moment it appears and posts a regular
notification instead:

    Keyboard
    Caps Lock
    Turned on

Urgency is `normal`: Ambxst only gives `critical` its alert/warning styling.
A key replaces its own previous notification (`replaceKey`), so repeated
toggling does not stack popups.

## Install

Settings > Mods > install from Git URL:

    https://github.com/Optinux/ambxst-mod-openlogi-lock-key.git

or open the install link (it asks for confirmation, new mods start disabled):

    ambxst://mods/install?source=https%3A%2F%2Fgithub.com%2FOptinux%2Fambxst-mod-openlogi-lock-key.git

Review the declared permissions, enable the mod, restart the shell. To undo:

    ambxst mods rollback

Compatibility: Ambxst `>=1.4.0 <1.5.0` (tested on base commit
`730f0f7bce1cc11740ac98ff3141f14bbc968fb2`). On another version, use the
**Bypass Ambxst version check** toggle in Settings > Mods or
`ambxst mods bypass on`.

## How it works

- Watches `AxctlService.clients` for a window with class
  `openlogi-lock-key-osd` and closes it (`closewindow address:...`).
- Finds out *which* key changed by following the keyboard LEDs
  (`/sys/class/leds/input*::{capslock,numlock,scrolllock}`), which the
  compositor keeps in sync with its xkb state. One long-lived `sh` loop reads
  them and only reports changes.
- Pairs each OSD window with an LED change (within 1 s, in either order) and
  posts one notification per pair. Because it waits for OpenLogi's window,
  OpenLogi's own `lock_key_notifications` setting still switches this on/off,
  and caps lock presses on keyboards OpenLogi does not manage stay silent.
- If the machine exposes no lock key LEDs at all, it falls back to a generic
  "Lock key / State changed" notification.

Only `openlogi-lock-key-osd` is touched. OpenLogi's backlight OSD, battery
notice and Actions Ring windows are left alone.

## Removing the last frame (optional, Hyprland >= 0.55)

The mod can only close the window once Ambxst learns about it, which can leave
one brief tiled frame. A compositor-side rule stops the window from ever
taking tiled space. Add
[`examples/hyprland-window-rule.lua`](examples/hyprland-window-rule.lua) to
the OVERRIDES section of your `hyprland.lua` and run `hyprctl reload`. If it
still flashes, check the class with `hyprctl clients | grep -B2 -A8 openlogi`.

## Tunables

Constants at the top of `payload/OpenLogiLockKey.qml`:

| Property | Default | Meaning |
|---|---|---|
| `requireOsdWindow` | `true` | `false` notifies on every lock key change from any keyboard |
| `closeOsdWindow` | `true` | `false` leaves OpenLogi's window alone |
| `expireTimeout` | `1500` | popup lifetime in ms |
| `correlationWindow` | `1000` | max ms between OpenLogi's window and the LED change |
| `pollInterval` | `"0.25"` | seconds between LED reads |

## Layout

    ambxst.mod.json                 manifest
    payload/OpenLogiLockKey.qml     added as modules/services/OpenLogiLockKey.qml
    patches/shell-init.patch        one line in shell.qml to start the singleton
    examples/                       optional Hyprland rule
    CHANGELOG.md  LICENSE  README.md

## License

AGPL-3.0-only, the same as Ambxst (the mod patches and extends its source).
Not affiliated with OpenLogi, Logitech or Ambxst.
