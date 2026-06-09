// Wayfire IPC client for the wayfire-curtain-peek plugin.
//
// Frame format (matches wf::ipc::server_t in /usr/lib64/wayfire/libipc.so):
//   [u32 LE payload-length] [JSON body bytes]
//
// JSON body shape:
//   {"method":"wayfire-curtain-peek/<name>","data":{}}
//
// The socket path comes from the env var Wayfire's `ipc` plugin exports
// (_WAYFIRE_SOCKET, leading underscore — easy to mistype). Without it, every
// call is a silent no-op so a stand-alone (non-Wayfire) test of lumen-desktop
// doesn't trip over a missing dep.
//
// lumen-desktop only ever needs to *close* the curtain (hide itself again) —
// it is revealed by the compositor-side binding, which also hands it keyboard
// focus. The single close() call on launch makes sure a restart doesn't leave
// the grid stranded visible if the curtain happened to be open.

namespace LumenDesktop {

    public class CurtainIpc : GLib.Object {

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
            if (path == null) {
                return false;
            }

            try {
                var client = new GLib.SocketClient();
                var addr   = new GLib.UnixSocketAddress(path);
                var conn   = client.connect(addr, null);

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

                // Best-effort: read a reply so the server-side handler runs
                // before we close. We don't parse it.
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
                    // No reply readable — fine, the request was already sent.
                }

                conn.close();
                return true;
            } catch (GLib.Error e) {
                GLib.stderr.printf("curtain_ipc: IPC error: %s\n", e.message);
                return false;
            }
        }

        // Close the curtain (hide the desktop grid). No-op when the curtain is
        // already idle on the compositor side.
        public static bool close() {
            return send_method("wayfire-curtain-peek/stop");
        }
    }
}
