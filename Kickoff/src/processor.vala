using DrawKit;
using WLHooks;
using GLES2;
using Gee;

public class Processor {
    private Context ctx;
    private AppEntry[] apps;

    private SearchBar searchbar;
    private SearchDb searchDb;

    private GridView main_grid;
    private SearchGridView search_grid;
    private unowned IGrid grid;

    private float bg_a;

    public Processor(int screen_width, int screen_height) {
        WLHooks.init_layer_shell("Kickoff-overlay", screen_width, screen_height, UP | LEFT | RIGHT | DOWN, false);

        ctx = Context.Init_with_groups(screen_width, screen_height, 2);

        var icon_paths = Utils.Icon.load_or_create_icon_cache(96);
        print("Num icons in cache: %i\n", icon_paths.size);

        var desktop_files = Utils.System.get_desktop_files();
        print("#desktop files: %i\n", desktop_files.length);

        var deduplication = new HashSet<string>();

        foreach (var desktop in desktop_files){
            var entries = Utils.Config.parse(desktop, "Desktop Entry");

            if (entries == null)
                continue;

            if (entry_is_hidden(entries))
                continue;

            var name = get_name(entries);
            var icon = entries["Icon"];
            var exec = entries["Exec"];
            
            if (name == null || exec == null || exec == "") 
                continue;

            
            if(deduplication.contains(name)) 
                continue;
            
            deduplication.add(name);

            var icon_path = resolve_icon_path(icon_paths, icon);
            if (icon_path == null)
                continue;
            
            apps += new AppEntry(name, icon_path, exec);
        }

        print("Apps: %i\n", apps.length);

        searchDb = new SearchDb(apps, screen_width, screen_height);
        searchbar = new SearchBar(ctx, screen_width);

        main_grid = new GridView(ctx, apps, screen_width, screen_height);
        search_grid = new SearchGridView(ctx, screen_width, screen_height);
        grid = main_grid;

        Main.animations.add(new Transition1D(0, &bg_a, 0.8f, 3));
    }

    /*  public void show_overlay (){
        WLHooks.init_layer_shell("Kickoff-overlay", screen_width, screen_height, UP | LEFT | RIGHT | DOWN, false);
    }  */

    public void mouse_move(int mouse_x, int mouse_y) {
        grid.mouse_move(mouse_x, mouse_y);
    }

    public void mouse_down(uint32 button) {
        if(button != 272) return;
        grid.mouse_down();
    }
    public void mouse_up(uint32 button) {
        if(button != 272) return;
        grid.mouse_up();
    }

    public void key_down(uint32 key){
        if(key == 65307){
            WLHooks.destroy();
            Process.exit (0);
        }

        searchDb.on_key(key);

        if(searchDb.active){
            grid = (IGrid) search_grid;
            search_grid.add(searchDb.filtered, searchDb.size);
        } else {
            grid = (IGrid) main_grid;
        }

        grid.key_down(key);
    }
    
    public void render() {
        ctx.set_bg_color(DrawKit.Color(){ r = 0, g =  0, b = 0, a = bg_a });
        
        ctx.begin_frame();

        searchbar.render(searchDb.get_search());
        grid.render();

        ctx.end_frame();
    }

    private static bool entry_is_hidden(HashMap<string, string> entries) {
        if (entries.has_key("Hidden") && entries["Hidden"].down() == "true")
            return true;

        if (entries.has_key("NoDisplay") && entries["NoDisplay"].down() == "true")
            return true;

        return false;
    }

    private static string? get_name(HashMap<string, string> entries) {
        if (entries.has_key("Name") && entries["Name"] != "")
            return entries["Name"];

        foreach (var key in entries.keys) {
            if (key.has_prefix("Name[") && entries[key] != "")
                return entries[key];
        }

        return null;
    }

    private static string? resolve_icon_path(HashMap<string, string> icon_paths, string? icon) {
        if (icon != null && icon != "") {
            if (Path.is_absolute(icon) && FileUtils.test(icon, FileTest.IS_REGULAR)) {
                return icon;
            }

            if (icon_paths.has_key(icon)) {
                return icon_paths[icon];
            }
        }

        string[] fallbacks = {
            "application-x-executable",
            "application-default-icon",
            "applications-other",
            "system-run"
        };

        foreach (var fallback in fallbacks) {
            if (icon_paths.has_key(fallback))
                return icon_paths[fallback];
        }

        return null;
    }

    //TODO main loop
    /*  public void main_loop(){

    }  */
}