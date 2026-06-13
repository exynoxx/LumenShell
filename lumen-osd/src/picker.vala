using Gtk;

/* Windows-style Win+P display picker, owned entirely client-side.
 *
 * A `<super> KEY_P` command binding pokes lumen-osd (via `lumen-osdctl
 * --display-picker`). We then show the centered selector AND take an exclusive
 * layer-shell keyboard grab, so from that point every key reaches us:
 *   - P            advance the highlight
 *   - Escape       cancel (apply nothing)
 *   - Super up     commit the highlighted mode
 *
 * Detecting the Super release is the whole reason for the grab — Wayfire's
 * command bindings only fire on press. The actual wlr-randr switch is delegated
 * to `lumen-osdctl --display-mode <key>` (keeping all display logic in the Vala
 * DisplayCtl); applying it makes lumen-osdctl call back into our show() with the
 * confirmation chip, which replaces the selector. */
public class Picker : Object {

    // Mirrors lumen-osdctl's DisplayCtl.Mode (icons/labels) and SELECTOR_MODES
    // order. Three stable entries — duplicated across the process boundary the
    // same way the old plugin held its own copy.
    private const string[] KEYS   = { "internal", "extend", "external" };
    private const string[] ICONS  = {
        "video-single-display-symbolic",
        "video-joined-displays-symbolic",
        "video-display-symbolic",
    };
    private const string[] LABELS = {
        "Built-in display",
        "Extend",
        "External display",
    };

    // Safety net: if key activity stops for this long (a missed Super-release,
    // or the user wandering off), cancel rather than hold the keyboard grab
    // forever. Re-armed on every keypress, so deliberate picking never trips it.
    private const uint IDLE_DISMISS_MS = 8000;

    private OsdWindow window;
    private bool      _active        = false;
    private bool      saw_super      = false;
    private bool      user_moved     = false;   // ignore async seed once touched
    private int       index          = 0;
    private int       last_index     = 0;        // remembered between invocations
    private uint      dismiss_source = 0;

    public bool active { get { return _active; } }

    public Picker(OsdWindow window) {
        this.window = window;

        var keys = new Gtk.EventControllerKey();
        // CAPTURE so we win over any focusable child the selector might gain.
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        keys.key_pressed.connect(on_key_pressed);
        keys.key_released.connect(on_key_released);
        keys.modifiers.connect(on_modifiers);
        ((Gtk.Widget) window).add_controller(keys);

        // Mouse: hover moves the highlight, click applies that tile.
        window.selector.hovered.connect((i) => { if (_active) move_to(i); });
        window.selector.chosen.connect((i)  => { if (_active) choose(i); });
    }

    // One <super> KEY_P binding-fire. Wayfire consumes Super+P at the compositor
    // (so it never reaches our grabbed surface) — which is exactly why each tap
    // arrives here as a fresh command invocation: open on the first, advance on
    // every subsequent tap while Super stays held.
    public void step() {
        if (!_active) {
            open();
        } else {
            advance();
        }
    }

    private void open() {
        _active    = true;
        saw_super  = false;
        user_moved = false;
        index      = last_index;

        refresh();
        window.grab_keyboard();
        window.set_visible(true);
        arm_dismiss();

        // Refine the initial highlight to the live mode, so a quick tap-release
        // is a no-op (Windows highlights the current mode). Async so it never
        // delays the grab; ignored if the user has already moved.
        seed_current_mode();
    }

    private void refresh() {
        window.selector.set_items(ICONS, LABELS, index);
        window.show_selector_view();
    }

    private void advance() {
        move_to((index + 1) % KEYS.length);
    }

    private void move_to(int i) {
        index      = i.clamp(0, KEYS.length - 1);
        user_moved = true;
        refresh();
        arm_dismiss();
    }

    private void choose(int i) {
        index      = i.clamp(0, KEYS.length - 1);
        user_moved = true;
        commit();
    }

    private void commit() {
        if (!_active) return;
        _active    = false;
        last_index = index;
        cancel_dismiss();

        window.release_keyboard();
        // Hide now; the apply below calls back into show() with the chip. If the
        // apply fails (no show() follows), the OSD simply stays hidden rather
        // than leaving the selector stuck on screen.
        window.set_visible(false);

        spawn({ "lumen-osdctl", "--display-mode", KEYS[index] });
    }

    private void cancel() {
        if (!_active) return;
        _active = false;
        cancel_dismiss();
        window.release_keyboard();
        window.set_visible(false);
    }

    private void arm_dismiss() {
        cancel_dismiss();
        dismiss_source = Timeout.add(IDLE_DISMISS_MS, () => {
            dismiss_source = 0;
            cancel();
            return Source.REMOVE;
        });
    }

    private void cancel_dismiss() {
        if (dismiss_source != 0) {
            Source.remove(dismiss_source);
            dismiss_source = 0;
        }
    }

    private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
        if (!_active) return false;
        switch (keyval) {
            case Gdk.Key.Escape:
                cancel();
                return true;
            case Gdk.Key.Left:
                move_to((index - 1 + KEYS.length) % KEYS.length);
                return true;
            case Gdk.Key.Right:
                move_to((index + 1) % KEYS.length);
                return true;
            case Gdk.Key.Return:
            case Gdk.Key.KP_Enter:
            case Gdk.Key.space:
                commit();
                return true;
            default:
                // P itself never reaches us — Wayfire consumes <super> KEY_P and
                // re-invokes step() instead. Swallow anything else to stay modal.
                return true;
        }
    }

    private void on_key_released(uint keyval, uint keycode, Gdk.ModifierType state) {
        if (!_active) return;
        if (keyval == Gdk.Key.Super_L || keyval == Gdk.Key.Super_R) commit();
    }

    // Backup commit path: some compositors deliver the release of an
    // already-held modifier only as a modifier-state change, not a key event.
    // Only fire once we've actually observed Super held (avoids committing on a
    // spurious zero-state at focus-in).
    private bool on_modifiers(Gdk.ModifierType state) {
        if (!_active) return false;
        bool super_now = (state & Gdk.ModifierType.SUPER_MASK) != 0;
        if (super_now) saw_super = true;
        else if (saw_super) commit();
        return false;
    }

    private void seed_current_mode() {
        try {
            var sp = new Subprocess(SubprocessFlags.STDOUT_PIPE,
                                    "lumen-osdctl", "--display-current");
            sp.communicate_utf8_async.begin(null, null, (obj, res) => {
                try {
                    string outp;
                    sp.communicate_utf8_async.end(res, out outp, null);
                    if (!_active || user_moved || outp == null) return;
                    string key = outp.strip();
                    for (int i = 0; i < KEYS.length; i++) {
                        if (KEYS[i] == key) { index = i; refresh(); break; }
                    }
                } catch (Error e) {
                    // Best-effort: keep the provisional highlight.
                }
            });
        } catch (Error e) {
            // lumen-osdctl missing / unspawnable: keep the provisional highlight.
        }
    }

    private static void spawn(string[] argv) {
        try {
            new Subprocess.newv(argv, SubprocessFlags.NONE);
        } catch (Error e) {
            warning("lumen-osd: failed to run %s: %s", argv[0], e.message);
        }
    }
}
