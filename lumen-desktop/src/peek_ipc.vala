// Wayfire IPC client for the wayfire-desktop-peek plugin.
//
// Frame format (matches wf::ipc::server_t in /usr/lib64/wayfire/libipc.so):
//   [u32 LE payload-length] [JSON body bytes]
//
// JSON body shape:
//   {"method":"wayfire-desktop-peek/<name>","data":{}}
//
// The socket path comes from the env var Wayfire's `ipc` plugin exports
// (_WAYFIRE_SOCKET, leading underscore — easy to mistype). Without it, every
// call is a silent no-op so a stand-alone (non-Wayfire) test of lumen-desktop
// doesn't trip over a missing dep.

namespace LumenDesktop {

    public class PeekIpc : GLib.Object {

        // Append-only log lives next to the C++ plugin's
        // /tmp/wayfire-desktop-peek.log so a single tail -f covers both sides.
        private const string LOG_PATH = "/tmp/lumen-desktop-peek.log";

        private static void log_line(string msg) {
            var ts = new GLib.DateTime.now_local();
            var line = "[%s] %s\n".printf(ts.format("%H:%M:%S.%f"), msg);
            try {
                var f = GLib.File.new_for_path(LOG_PATH);
                var os = f.append_to(GLib.FileCreateFlags.NONE);
                os.write(line.data);
                os.close();
            } catch (GLib.Error e) {
                // Best-effort: fall back to stderr if /tmp is somehow unwritable.
                GLib.stderr.printf("peek_ipc: %s (log write failed: %s)\n", msg, e.message);
            }
        }

        private static string? socket_path() {
            var p = GLib.Environment.get_variable("_WAYFIRE_SOCKET");
            if (p != null && p != "") {
                return p;
            }
            p = GLib.Environment.get_variable("WAYFIRE_SOCKET");
            if (p != null && p != "") {
                return p;
            }
            return null;
        }

        private static bool send_method(string method) {
            var path = socket_path();
            log_line(@"send_method '$method': socket=$(path ?? "<unset>")");
            if (path == null) {
                log_line("  no socket env var set — silent no-op");
                return false;
            }

            try {
                var client = new GLib.SocketClient();
                var addr   = new GLib.UnixSocketAddress(path);
                var conn   = client.connect(addr, null);
                log_line("  connected");

                var body  = @"{\"method\":\"$method\",\"data\":{}}";
                var bytes = body.data;
                uint32 len = (uint32) bytes.length;

                uint8 hdr[4];
                hdr[0] = (uint8) (len        & 0xff);
                hdr[1] = (uint8) ((len >> 8 ) & 0xff);
                hdr[2] = (uint8) ((len >> 16) & 0xff);
                hdr[3] = (uint8) ((len >> 24) & 0xff);

                var os = conn.get_output_stream();
                os.write_all(hdr, null, null);
                os.write_all(bytes, null, null);
                os.flush();
                log_line(@"  wrote $(4 + bytes.length) bytes");

                // Best-effort: read a reply so the server-side handler runs
                // before we close. We don't parse it — the C++ plugin already
                // logs everything we'd assert on.
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
                        var rstr = (string) rbuf;
                        log_line(@"  reply: $rstr");
                    } else {
                        log_line(@"  short reply header ($got bytes)");
                    }
                } catch (GLib.Error e) {
                    log_line(@"  no reply readable: $(e.message)");
                }

                conn.close();
                return true;
            } catch (GLib.Error e) {
                log_line(@"  IPC error: $(e.message)");
                return false;
            }
        }

        public static bool toggle() {
            return send_method("wayfire-desktop-peek/toggle");
        }

        public static bool start() {
            return send_method("wayfire-desktop-peek/start");
        }

        public static bool stop() {
            return send_method("wayfire-desktop-peek/stop");
        }
    }
}
