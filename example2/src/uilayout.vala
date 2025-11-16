using DrawKit;
using LayerShell;
using GLES2;

public class UiLayout {
    public static void Draw(DrawKit.Context ctx, MouseInfo *mouse, List<Program> programs){
        ctx.begin_frame();

        ctx.reset();
        ctx.start_box(0, 0);
            ctx.box_float(DrawKit.FloatMode.NONE);

            /*  ctx.start_box(0, 0);
                ctx.box_float(DrawKit.FloatMode.LEFT);
                ctx.box_set_gap(32);

                var b1 = ctx.rect(50, 50, Color(){r=1,g=1,b=1,a=0.1f});
                var b2 = ctx.rect(50, 50, Color(){r=1,g=1,b=1,a=0.1f});
                var b3 = ctx.rect(50, 50, Color(){r=1,g=1,b=1,a=0.1f});

            ctx.end_box();  */

            ctx.start_box(0, 0);
                ctx.box_float(DrawKit.FloatMode.LEFT);
                var padding = (50-32)/2;
                ctx.box_set_padding(padding, padding, padding, padding);
                ctx.box_set_gap(50);

                foreach (var item in programs)
                {
                    ctx.texture(item.tex, 32, 32);
                }

            ctx.end_box();

        ctx.end_box();

        DrawKit.Context.evaluate_positions(ctx.node_mngr.root,0,0);
        ctx.hitbox_query((int)mouse->mouse_x, (int)mouse->mouse_y);

        /*  if(b1.hovered) b1.color.a = 1;
        if(b2.hovered) b2.color.a = 1;
        if(b3.hovered) b3.color.a = 1;  */

        ctx.draw(0,0);
        ctx.end_frame();
    }
}