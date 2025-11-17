using DrawKit;
using LayerShell;
using GLES2;
using Gee;

public class UiLayout {

    public static void Draw(DrawKit.Context ctx, MouseInfo *mouse, Gee.List<Program> programs, int active_idx){

        var n_programs = programs.size;
        int underline_height = 5;
        int box_width = 70;
        int box_height = ctx.screen_height - underline_height;

        //print("drawing %d programs\n", n_programs);
        if(n_programs > 100){
            print("too many\n");
            Process.exit(1);
        }

        ctx.begin_frame();

        ctx.reset();
        ctx.start_box(0, 0);
            ctx.box_float(DrawKit.FloatMode.NONE);

            ctx.start_box(0, 0);
                ctx.box_float(DrawKit.FloatMode.LEFT);

                var hitboxes = new DrawKit.UINode*[n_programs];
                for(int i = 0; i < n_programs; i++){
                    hitboxes[i] = ctx.rect(box_width, box_height, Color(){r=1,g=1,b=1,a=0f});
                }

            ctx.end_box();

            ctx.start_box(0, 0);
                ctx.box_float(DrawKit.FloatMode.LEFT);
                var padding_side = (box_width-32)/2;
                var padding_top = (box_height-32)/2;

                foreach (var item in programs)
                {
                    ctx.texture(item.tex, 32, 32);
                    ctx.set_padding(padding_side, padding_side, padding_top);
                }
            ctx.end_box();
                    
            float shade = 0.15f;
            ctx.rect(0, underline_height, Color(){r=shade,g=shade,b=shade,a=1});
            ctx.set_padding(0, 0, box_height);

            if(active_idx >= 0){
                ctx.rect(box_width, underline_height, Color(){r=0,g=0.17f,b=0.9f,a=1});
                ctx.set_padding(active_idx*box_width, 0, box_height);
            }

        ctx.end_box();

        DrawKit.Context.evaluate_positions(ctx.node_mngr.root,0,0);
        ctx.hitbox_query((int)mouse->mouse_x, (int)mouse->mouse_y);

        foreach (var hitbox in hitboxes){
            if(hitbox.hovered) hitbox.color.a = 0.2f;
        }

        ctx.draw(0,0);
        ctx.end_frame();
    }
}