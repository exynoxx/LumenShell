
public class ExitTray : TrayIcon {

    // Wider slot to fit two labelled option buttons side-by-side.
    private const int EXIT_EXPANDED_WIDTH = 260;
    // Pixel offset where the option area begins (past the icon + a small gap).
    private const int OPT_OFFSET = ICON_SIZE + 8;

    // Which option area the cursor is currently over: 0=none, 1=Close App, 2=Shutdown
    private int option_hovered = 0;

    public ExitTray() {
        base("close");
    }

    protected override int get_expanded_width() {
        return EXIT_EXPANDED_WIDTH;
    }

    // Non-empty return enables the base expand mechanics; the actual content is
    // rendered by our render() override, so this text is never drawn directly.
    protected override string get_detail_text() {
        return "exit";
    }

    public override void mouse_motion(int mouse_x, int mouse_y) {
        base.mouse_motion(mouse_x, mouse_y);

        int prev = option_hovered;
        option_hovered = 0;

        // Track which option button the cursor is over while the slot is open.
        if (expanded && current_width > COLLAPSED_WIDTH + MIN_EXPAND_THRESHOLD) {
            int opt_start = render_x + OPT_OFFSET;
            int opt_total = current_width - OPT_OFFSET;
            int half = opt_total / 2;

            if (mouse_x >= opt_start && mouse_x < opt_start + half)
                option_hovered = 1;
            else if (mouse_x >= opt_start + half && mouse_x < render_x + current_width)
                option_hovered = 2;
        }

        if (option_hovered != prev)
            redraw = true;
    }

    public override void mouse_down() {
        if (!expanded) {
            // Expand on icon click.
            if (hovered) {
                expanded = true;
                animations.add(new Transition1D(anim_id, &current_width, EXIT_EXPANDED_WIDTH, 0.4));
                redraw = true;
            }
        } else {
            if (option_hovered == 1) {
                // Close the currently focused application.
                try {
                    Process.spawn_command_line_async("wlrctl window focus kill");
                } catch (Error e) {
                    warning("ExitTray: close app failed: %s", e.message);
                }
                collapse();
            } else if (option_hovered == 2) {
                // Shut down the system.
                try {
                    Process.spawn_command_line_async("systemctl poweroff");
                } catch (Error e) {
                    warning("ExitTray: shutdown failed: %s", e.message);
                }
            } else if (hovered) {
                // Clicking the icon while expanded collapses the prompt.
                collapse();
            }
        }
    }

    public override void mouse_up() {}

    private void collapse() {
        expanded = false;
        option_hovered = 0;
        animations.add(new Transition1D(anim_id, &current_width, COLLAPSED_WIDTH, 0.4));
        redraw = true;
    }

    public override void render(Context ctx) {
        render_icon(ctx);

        if (current_width > COLLAPSED_WIDTH + MIN_EXPAND_THRESHOLD) {
            float progress = float.min(
                (float)(current_width - COLLAPSED_WIDTH) / (float)(EXIT_EXPANDED_WIDTH - COLLAPSED_WIDTH),
                1.0f);

            int opt_start = render_x + OPT_OFFSET;
            int opt_total = current_width - OPT_OFFSET;
            int half = opt_total / 2;
            int btn_h = ICON_SIZE + 4;
            int text_y = render_y + ICON_SIZE / 2 + 4;

            // Option hover highlight backgrounds.
            if (option_hovered == 1) {
                ctx.draw_rect_rounded(opt_start, render_y - 2, half, btn_h, 8,
                    {0.3f, 0.3f, 0.3f, progress});
            }
            if (option_hovered == 2) {
                ctx.draw_rect_rounded(opt_start + half, render_y - 2, half, btn_h, 8,
                    {0.65f, 0.12f, 0.12f, progress});
            }

            // Centred labels for each option.
            ctx.draw_text("Close App", opt_start + half / 2, text_y, 13, {1, 1, 1, progress});
            ctx.draw_text("Shutdown",  opt_start + half + half / 2, text_y, 13, {1, 1, 1, progress});
        }
    }
}
