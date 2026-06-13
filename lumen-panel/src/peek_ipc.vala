// Wayfire IPC client for the wayfire-desktop-peek plugin.
//
// Only compiled into the panel when the `with_panel_peek` meson option is on
// (it gates the PANEL_PEEK define). A standalone panel build omits this file
// entirely and never talks to Wayfire.
//
// Mirrors lumen-desktop/src/peek_ipc.vala — see that file for the full notes
// on the frame format and the _WAYFIRE_SOCKET env var. The panel only needs
// to toggle the peek, so this is trimmed to the one method.
#if PANEL_PEEK
public class PeekIpc : GLib.Object {

    private static string? socket_path () {
        var p = GLib.Environment.get_variable("_WAYFIRE_SOCKET");
        if (p != null && p != "") return p;
        p = GLib.Environment.get_variable("WAYFIRE_SOCKET");
        if (p != null && p != "") return p;
        return null;
    }

    private static bool send_method (string method) {
        var path = socket_path();
        // Without the env var (e.g. running the panel outside Wayfire) every
        // call is a silent no-op rather than a crash.
        if (path == null) return false;

        try {
            var client = new GLib.SocketClient();
            var addr   = new GLib.UnixSocketAddress(path);
            var conn   = client.connect(addr, null);

            var body  = @"{\"method\":\"$method\",\"data\":{}}";
            var bytes = body.data;
            uint32 len = (uint32) bytes.length;

            uint8 hdr[4];
            hdr[0] = (uint8) (len         & 0xff);
            hdr[1] = (uint8) ((len >> 8 ) & 0xff);
            hdr[2] = (uint8) ((len >> 16) & 0xff);
            hdr[3] = (uint8) ((len >> 24) & 0xff);

            var os = conn.get_output_stream();
            os.write_all(hdr, null, null);
            os.write_all(bytes, null, null);
            os.flush();

            // Read the reply header so the server-side handler runs before we
            // close the connection. We don't parse it.
            var is = conn.get_input_stream();
            uint8 reply_hdr[4];
            size_t got;
            try {
                is.read_all(reply_hdr, out got, null);
                if (got == 4) {
                    uint32 rl = ((uint32) reply_hdr[0])
                              | (((uint32) reply_hdr[1]) << 8)
                              | (((uint32) reply_hdr[2]) << 16)
                              | (((uint32) reply_hdr[3]) << 24);
                    var rbuf = new uint8[rl];
                    is.read_all(rbuf, out got, null);
                }
            } catch (GLib.Error e) {
                // Reply is best-effort; ignore.
            }

            conn.close();
            return true;
        } catch (GLib.Error e) {
            GLib.stderr.printf("peek_ipc: IPC error: %s\n", e.message);
            return false;
        }
    }

    public static bool toggle () {
        return send_method("wayfire-desktop-peek/toggle");
    }

    // Toggle the app-drawer reveal (lumen-desktop). Only one of curtain-peek /
    // slide-peek is ever loaded, so the toggle for the inactive one is a
    // harmless no-op (its IPC method isn't registered) — same pattern as
    // lumen-desktop's CurtainIpc.close(). Used by the optional launcher button.
    public static bool app_drawer () {
        bool a = send_method("wayfire-curtain-peek/toggle");
        bool b = send_method("wayfire-slide-peek/toggle");
        return a || b;
    }
}
#endif
