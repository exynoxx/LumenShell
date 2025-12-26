using GLES2;

public class AppEntry {
    public string name;
    public string short_name;
    public string exec;
    public GLuint tex;

    public AppEntry(string name, string icon_path, string exec){
        this.short_name = name.char_count() > 20 ? name.substring(0, 20) + "..." : name;
        this.name = name;
        this.exec = exec;
        this.tex = Utils.Image.Upload_texture(icon_path, ICON_SIZE);
    }

    public void launch_app() {
        stdout.printf("Launching: %s (%s)\n", name, exec);
        
        try {
            Process.spawn_command_line_async(exec);
        } catch (SpawnError e) {
            stderr.printf("Failed to launch %s: %s\n", name, e.message);
        }

        WLHooks.destroy();
        Process.exit (0);
    }
}