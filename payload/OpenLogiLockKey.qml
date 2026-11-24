pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services

/**
 * OpenLogiLockKey
 *
 * OpenLogi shows its "lock key" indicator ("Caps Lock On", ...) as a real
 * toplevel window (app_id `openlogi-lock-key-osd`). On a tiling compositor
 * that window gets tiled and takes half the workspace.
 *
 * This singleton:
 *   1. notices that window through the compositor state Ambxst already
 *      tracks (AxctlService.clients) and closes it right away;
 *   2. works out which lock key changed by following the keyboard LEDs in
 *      /sys/class/leds (the compositor keeps them in sync with its xkb state);
 *   3. posts an ordinary (non-critical) Ambxst notification for that change.
 *
 * Window appearances and LED changes arrive independently, so they are
 * paired up within `correlationWindow` ms. A change nobody announced (for
 * example a laptop keyboard OpenLogi does not manage) therefore stays silent,
 * unless `requireOsdWindow` is turned off.
 */
Singleton {
    id: root

    // ---- Tunables ---------------------------------------------------------
    readonly property string osdAppId: "openlogi-lock-key-osd"
    // true:  notify only when OpenLogi announced the change (follows OpenLogi's
    //        own `lock_key_notifications` setting).
    // false: notify on every lock key change, from any keyboard.
    readonly property bool requireOsdWindow: true
    readonly property bool closeOsdWindow: true
    readonly property int expireTimeout: 1500
    readonly property int correlationWindow: 1000
    readonly property string pollInterval: "0.25"
    // Informative, not a warning: only "critical" gets Ambxst's alert styling.
    readonly property string urgency: "normal"

    // Touched from shell.qml to instantiate the singleton at startup.
    readonly property bool active: true

    // ---- State ------------------------------------------------------------
    property var seen: ({})          // OSD window addresses already handled
    property var leds: null          // {caps, num, scroll}: "1" | "0" | "-"
    property var changes: []         // unmatched LED changes {key, on, t}
    property var appearances: []     // unmatched OSD appearances {t}

    readonly property var keyNames: ({
        caps: "Caps Lock",
        num: "Num Lock",
        scroll: "Scroll Lock"
    })

    readonly property bool ledsUnavailable: root.leds === null
        || (root.leds.caps === "-" && root.leds.num === "-" && root.leds.scroll === "-")

    // ---- OSD window handling ---------------------------------------------
    Connections {
        target: AxctlService.clients

        function onValuesChanged() {
            root.scanWindows();
        }
    }

    function scanWindows() {
        const clients = AxctlService.clients.values || [];
        const present = {};
        let appeared = 0;

        for (let i = 0; i < clients.length; i++) {
            const client = clients[i];
            if (!client || client.class !== root.osdAppId) continue;
            present[client.address] = true;
            if (root.seen[client.address]) continue;

            root.seen[client.address] = true;
            appeared++;
            if (root.closeOsdWindow)
                AxctlService.dispatch("closewindow address:" + client.address);
        }

        for (const address in root.seen) {
            if (!present[address]) delete root.seen[address];
        }

        if (appeared > 0) root.onOsdAppeared(appeared);
    }

    // ---- Lock key state (keyboard LEDs) ----------------------------------
    // One long-lived loop that prints a line like "010" (caps, num, scroll;
    // 1 = on, 0 = off, - = no LED found) only when the value changes.
    Process {
        id: ledWatcher
        running: true
        command: ["sh", "-c", `
            prev=
            while :; do
                out=
                for k in capslock numlock scrolllock; do
                    s=-
                    for f in /sys/class/leds/input*::"$k"/brightness; do
                        [ -r "$f" ] || continue
                        s=0
                        read -r v < "$f" 2>/dev/null || continue
                        if [ "\${v:-0}" != 0 ]; then s=1; break; fi
                    done
                    out="$out$s"
                done
                if [ "$out" != "$prev" ]; then
                    printf '%s\\n' "$out" || exit 0
                    prev=$out
                fi
                sleep ${root.pollInterval}
            done
        `]

        stdout: SplitParser {
            onRead: data => root.onLeds(data)
        }
    }

    function onLeds(line) {
        const s = String(line).trim();
        if (s.length !== 3) return;

        const next = {caps: s[0], num: s[1], scroll: s[2]};
        const previous = root.leds;
        root.leds = next;
        if (previous === null) return; // first reading is only the baseline

        const now = Date.now();
        for (const key of ["caps", "num", "scroll"]) {
            if (next[key] === previous[key] || next[key] === "-" || previous[key] === "-")
                continue;
            const on = next[key] === "1";
            if (root.requireOsdWindow)
                root.changes.push({key: key, on: on, t: now});
            else
                root.notifyChange(key, on);
        }
        root.match();
    }

    // ---- Pairing ----------------------------------------------------------
    function onOsdAppeared(count) {
        if (!root.requireOsdWindow) return;
        const now = Date.now();
        for (let i = 0; i < count; i++)
            root.appearances.push({t: now});
        root.match();
    }

    function match() {
        root.prune();
        while (root.changes.length > 0 && root.appearances.length > 0) {
            const change = root.changes.shift();
            root.appearances.shift();
            root.notifyChange(change.key, change.on);
        }
        if (root.changes.length > 0 || root.appearances.length > 0)
            expiry.restart();
    }

    // Drop what stayed unpaired for too long. An unpaired appearance means
    // OpenLogi announced something we cannot identify; if this machine has
    // no lock key LEDs at all, say so generically instead of staying silent.
    function prune() {
        const limit = Date.now() - root.correlationWindow;
        root.changes = root.changes.filter(item => item.t >= limit);
        const expired = root.appearances.filter(item => item.t < limit);
        root.appearances = root.appearances.filter(item => item.t >= limit);
        if (root.ledsUnavailable) {
            for (let i = 0; i < expired.length; i++)
                root.notifyGeneric();
        }
    }

    Timer {
        id: expiry
        interval: root.correlationWindow + 50
        repeat: false
        onTriggered: root.match()
    }

    // ---- Notifications ----------------------------------------------------
    function notifyChange(key, on) {
        Notifications.notifyInternal({
            appName: "Keyboard",
            appIcon: "input-keyboard",
            summary: root.keyNames[key],
            body: on ? "Turned on" : "Turned off",
            urgency: root.urgency,
            expireTimeout: root.expireTimeout,
            // Same key replaces its previous notification instead of stacking.
            replaceKey: "openlogi-lock-key-" + key
        });
    }

    function notifyGeneric() {
        Notifications.notifyInternal({
            appName: "Keyboard",
            appIcon: "input-keyboard",
            summary: "Lock key",
            body: "State changed",
            urgency: root.urgency,
            expireTimeout: root.expireTimeout,
            replaceKey: "openlogi-lock-key-generic"
        });
    }

    Component.onCompleted: root.scanWindows()
}
