// Quick Share tile in GNOME's Quick Settings, for rQuickShare (a Quick Share client).
// rQuickShare can't be controlled from outside, so the toggle starts and quits it:
// on = running (hidden, started minimised) and visible to nearby Android phones;
// off = not running, nothing advertised, no memory used. While it's on, an icon
// sits in the top bar. The state is re-checked whenever Quick Settings opens.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {QuickMenuToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const BINARY = 'rquickshare';
const ICON = 'send-to-symbolic';

function installed() {
    return GLib.find_program_in_path(BINARY) !== null;
}

// Run argv; calls done(ok, stdout) when it exits.
function run(argv, done) {
    try {
        const proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        proc.communicate_utf8_async(null, null, (p, res) => {
            let out = '';
            try {
                [, out] = p.communicate_utf8_finish(res);
            } catch {}
            done?.(p.get_successful(), out ?? '');
        });
    } catch (e) {
        logError(e, 'quick-share');
        done?.(false, '');
    }
}

const QuickShareToggle = GObject.registerClass(
class QuickShareToggle extends QuickMenuToggle {
    _init(onStateChanged) {
        super._init({title: 'Quick Share', iconName: ICON, toggleMode: false});
        this._onStateChanged = onStateChanged;
        this._running = false;

        this.menu.setHeader(ICON, 'Quick Share', 'Send and receive with nearby Android devices');
        this.menu.addAction('Open rQuickShare', () => this._open());
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addMenuItem(new PopupMenu.PopupMenuItem(
            'Receive: on the phone, Share → Quick Share → this laptop.\n' +
            'Send: open rQuickShare and drop the files in.', {reactive: false}));

        this.connect('clicked', () => (this._running ? this._stop() : this._start()));
        this.refresh();
    }

    refresh() {
        if (!installed()) {
            this._set(false);
            return;
        }
        run(['pgrep', '-x', BINARY], ok => this._set(ok));
    }

    _set(running) {
        this._running = running;
        const ok = installed();
        this.set({
            checked: running,
            reactive: ok,
            subtitle: !ok ? 'rQuickShare not installed' : running ? 'Receiving' : 'Off',
        });
        this._onStateChanged(running);
    }

    // Starts hidden (install.sh sets startminimized); refresh when it exits.
    _start(thenShow = false) {
        try {
            const proc = Gio.Subprocess.new([BINARY], Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
            proc.wait_async(null, () => this.refresh());
        } catch (e) {
            logError(e, 'quick-share');
            Main.notify('Quick Share', "Couldn't start rQuickShare.");
            return;
        }
        this._set(true);
        if (thenShow) {
            // A second launch makes the running instance show its window
            GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3, () => {
                run([BINARY]);
                return GLib.SOURCE_REMOVE;
            });
        }
    }

    _stop() {
        run(['pkill', '-TERM', '-x', BINARY], () => this.refresh());
        this._set(false);
    }

    _open() {
        if (!installed())
            return;
        if (this._running)
            run([BINARY]);
        else
            this._start(true);
    }
});

const QuickShareIndicator = GObject.registerClass(
class QuickShareIndicator extends SystemIndicator {
    _init() {
        super._init();
        this._icon = this._addIndicator();
        this._icon.iconName = ICON;
        this._icon.visible = false;
        this.toggle = new QuickShareToggle(running => (this._icon.visible = running));
        this.quickSettingsItems.push(this.toggle);
    }
});

export default class QuickShareExtension extends Extension {
    enable() {
        this._indicator = new QuickShareIndicator();
        const qs = Main.panel.statusArea.quickSettings;
        qs.addExternalIndicator(this._indicator);
        // Re-check when Quick Settings opens (rQuickShare may have been started/quit elsewhere)
        this._openId = qs.menu.connect('open-state-changed', (_m, open) => {
            if (open)
                this._indicator.toggle.refresh();
        });
    }

    disable() {
        Main.panel.statusArea.quickSettings.menu.disconnect(this._openId);
        this._indicator.quickSettingsItems.forEach(item => item.destroy());
        this._indicator.destroy();
        this._indicator = null;
    }
}
