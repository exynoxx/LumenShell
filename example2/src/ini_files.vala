//gtk-icon-theme-name

public class Ini {
    public static string? Get_key_value(string file_path, string key){
        if (!FileUtils.test(file_path, FileTest.EXISTS))
        return null;

        string? value = null;
        try {

            FileStream stream = FileStream.open (file_path, "r");
            assert (stream != null);

            string? line = null;
            while ((line = stream.read_line ()) != null) {
                string l = line.strip();
                if(!l.contains("=")){
                    continue;
                }

                string[] parts = l.split("=", 2);
                if (parts[0].strip() == key) {
                    value = parts[1].strip();
                    break;
                }
            }
        } catch (Error e) {
            warning("Failed to read INI file '%s': %s", file_path, e.message);
        }
        return value;
    }
}