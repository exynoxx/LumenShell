// Throwaway diagnostic logger — writes timestamped lines to a fixed tmp file
// AND stderr, flushed immediately so a tail -f sees events live. Used to chase
// the "dialog renders but buttons do nothing" bug. Remove once resolved.
[PrintfFormat]
void lpa_dbg(string fmt, ...) {
    var l = va_list();
    var body = fmt.vprintf(l);
    var ts = new DateTime.now_local().format("%H:%M:%S");
    var line = "%s  %s".printf(ts, body);

    var f = FileStream.open("/tmp/lumen-polkit-agent-dbg.log", "a");
    if (f != null) {
        f.puts(line);
        f.putc('\n');
        f.flush();
    }
    stderr.puts(line);
    stderr.putc('\n');
    stderr.flush();
}
