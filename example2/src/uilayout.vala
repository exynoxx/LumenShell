using DrawKit;
using LayerShell;
using GLES2;
using Gee;

public class UiLayout {

    const int padding_side = (box_width-32)/2;
    const int padding_top = (box_height-32)/2;

    const int width = 1920;
    const int height = 60;
    const int box_width = 70;
    const int box_height = 55;
    const int underline_height = 5;

    private static void Draw_box(DrawKit.Context ctx, Node box, ref int content_x){
        var color = Color(){r=1,g=1,b=1,a=0f};
        if (box.hovered) color.a = 0.2f; 
        ctx.draw_rect(box.x, box.y, box_width, box_height, color);
        content_x+=padding_side;
        ctx.draw_texture(box.tex, content_x, padding_top, 32, 32);
        content_x+=32+padding_side;
    }

    public static void Draw(DrawKit.Context ctx, Gee.List<Node> entries, int active_idx){
        ctx.begin_frame();

        var content_x = 0;
        
        //launcher
        Draw_box(ctx, entries[0], ref content_x);

        //sep
        ctx.draw_rect(content_x, 10, 2, box_height-20, Color(){r=0,g=0,b=0,a=1});
        content_x +=2;

        //open programs
        for(var i = 1; i<entries.size; i++){
            Draw_box(ctx, entries[i], ref content_x);
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