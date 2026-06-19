using Gee;
using GLib;

public class Ini {
    // Read one key from a grouped INI file via GLib.KeyFile. Returns null if the
    // file/group/key is absent or unparseable (fail-soft, same contract as the
    // old line scanner). Value is stripped so trailing/leading spaces from the
    // "key = value" writer never leak into comparisons.
    public static string? get_value(string file_path, string group, string key) {
        if (!FileUtils.test(file_path, FileTest.EXISTS)) return null;
        var kf = new KeyFile();
        try {
            kf.load_from_file(file_path, KeyFileFlags.NONE);
            if (!kf.has_group(group) || !kf.has_key(group, key)) return null;
            return kf.get_string(group, key).strip();
        } catch (Error e) {
            return null;
        }
    }

    public static ArrayList<string> read_lines(string file_path){
        var lines = new ArrayList<string>();
        if (!FileUtils.test(file_path, FileTest.EXISTS)) {
            return lines;
        }

        try {
            string content;
            size_t len;
            FileUtils.get_contents(file_path, out content, out len);
            foreach (var line in content.split("\n")) {
                var trimmed = line.strip();
                if(trimmed != "") lines.add(trimmed);
            }
        } catch (Error e) {
            stderr.printf("Failed reading %s: %s\n", file_path, e.message);
        }

        return lines;
    }

    public static void write_lines(string file_path, Gee.List<string> lines){
        var parent = Path.get_dirname(file_path);
        try {
            DirUtils.create_with_parents(parent, 0755);
        } catch (Error e) {
            stderr.printf("Failed creating dir %s: %s\n", parent, e.message);
            return;
        }

        var sb = new StringBuilder();
        foreach (var line in lines) {
            sb.append(line);
            sb.append("\n");
        }

        try {
            FileUtils.set_contents(file_path, sb.str);
        } catch (Error e) {
            stderr.printf("Failed writing %s: %s\n", file_path, e.message);
        }
    }
}
