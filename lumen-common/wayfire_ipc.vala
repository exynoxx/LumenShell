// Shared Wayfire IPC client (lumen-common).
//
// Frame format (matches wf::ipc::server_t in /usr/lib64/wayfire/libipc.so):
//   [u32 LE payload-length] [JSON body bytes]
//
// JSON body shape:
//   {"method":"<plugin>/<verb>","data":{}}
//
// The socket path comes from the env var Wayfire's `ipc` plugin exports
// (_WAYFIRE_SOCKET, leading underscore — easy to mistype; falls back to
// WAYFIRE_SOCKET). Without it — e.g. running a binary outside Wayfire — every
// call is a silent no-op so a stand-alone test doesn't trip over a missing dep.
//
// Source-level reuse only (no shared .so): added to lumen-desktop (always) and
// lumen-panel (under with_panel_peek). Callers keep their own thin verb
// wrappers — lumen-panel/src/peek_ipc.vala, lumen-desktop/src/curtain_ipc.vala.

namespace LumenCommon {

    public class WayfireIpc : GLib.Object {

        public static string? socket_path() {
            var p = GLib.Environment.get_variable("_WAYFIRE_SOCKET");
            if (p != null && p != "") return p;
            p = GLib.Environment.get_variable("WAYFIRE_SOCKET");
            if (p != null && p != "") return p;
            return null;
        }

        // Send one {"method":...} request and read the reply header so the
        // server-side handler runs before we close. Returns false on no socket
        // or any IPC error; the reply payload is read best-effort and discarded.
        public static bool send_method(string method) {
            var path = socket_path();
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
                GLib.stderr.printf("wayfire-ipc: IPC error: %s\n", e.message);
                return false;
            }
        }
    }
}
