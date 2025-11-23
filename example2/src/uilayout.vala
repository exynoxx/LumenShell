using DrawKit;
using LayerShell;
using GLES2;
using Gee;

public class UiLayout {

    public static void Draw(DrawKit.Context ctx, Gee.List<Node> entries, int active_idx){

        int n_entries = entries.size;

        int width = 1920;
        int height = 60;
        int box_width = 70;
        int underline_height = 5;
        int box_height = height - underline_height;

        var padding_side = (box_width-32)/2;
        var padding_top = (box_height-32)/2;
        var content_x = 0;

        if(n_entries > 100){
            print("too many\n");
            Process.exit(1);
        }

        ctx.begin_frame();
        foreach (var box in entries){
            var color = Color(){r=1,g=1,b=1,a=0f};
            if (box.hovered) color.a = 0.2f; 
            ctx.draw_rect(box.x, box.y, box_width, box_height, color);
            content_x+=padding_side;
            ctx.draw_texture(box.tex, content_x, padding_top, 32, 32);
            content_x+=32+padding_side;
        }

        //underline
        float shade = 0.15f;
        ctx.draw_rect(0, box_height, width, underline_height, Color(){r=shade,g=shade,b=shade,a=1});

        //active
        if(active_idx >= 0){
            var color = Color(){r=0,g=0.17f,b=0.9f,a=1};
            ctx.draw_rect(active_idx*box_width, box_height, box_width, underline_height, color);
        }

        ctx.end_frame();
    }
}