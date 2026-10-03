// Quick Share panel applet for Cinnamon (Linux Mint), for rQuickShare. Same idea as
// the GNOME tile: rQuickShare can't be controlled from outside, so the switch starts
// it (hidden, started minimised) and quits it. On = visible to nearby Android phones;
// off = not running, nothing advertised. The icon is dimmed while it's off, and the
// state is re-checked whenever the menu opens.
const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Main = imports.ui.main;
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;

const BINARY = 'rquickshare';
const ICON = 'send-to-symbolic';

function installed() {
    return GLib.find_program_in_path(BINARY) !== null;
}

// Run argv; calls done(ok) when it exits.
function run(argv, done) {
    try {
        const proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
        proc.wait_async(null, (p, res) => {
            try {
                p.wait_finish(res);
            } catch (e) {}
            if (done)
                done(p.get_successful());
        });
    } catch (e) {
        global.logError(`quick-share: ${e}`);
        if (done)
            done(false);
    }
}

class QuickShareApplet extends Applet.IconApplet {
    constructor(metadata, orientation, panelHeight, instanceId) {
        super(orientation, panelHeight, instanceId);
        this.set_applet_icon_symbolic_name(ICON);
        this._running = false;

        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);

        this._switch = new PopupMenu.PopupSwitchMenuItem('Quick Share', false);
        this._switch.connect('toggled', (_item, on) => (on ? this._start() : this._stop()));
        this.menu.addMenuItem(this._switch);
        this.menu.addAction('Open rQuickShare', () => this._open());
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        const hint = new PopupMenu.PopupMenuItem(
            'Receive: on the phone, Share → Quick Share → this laptop.\n' +
            'Send: open rQuickShare and drop the files in.', {reactive: false});
        this.menu.addMenuItem(hint);

        this.menu.connect('open-state-changed', (_m, open) => {
            if (open)
                this.refresh();
        });
        this.refresh();
    }

    on_applet_clicked() {
        this.menu.toggle();
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
        this._switch.setToggleState(running);
        this._switch.setSensitive(ok);
        this.actor.opacity = running ? 255 : 120;
        this.set_applet_tooltip(!ok ? 'Quick Share: rQuickShare not installed'
            : running ? 'Quick Share: receiving' : 'Quick Share: off');
    }

    // Starts hidden (install.sh sets startminimized); refresh when it exits.
    _start(thenShow = false) {
        if (!installed())
            return;
        run([BINARY], () => this.refresh());
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
        if (this._running)
            run([BINARY]);
        else
            this._start(true);
    }
}

function main(metadata, orientation, panelHeight, instanceId) {
    return new QuickShareApplet(metadata, orientation, panelHeight, instanceId);
}
