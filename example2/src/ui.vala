using DrawKit;
using LayerShell;

public class UI {
    public static void Draw(DrawKit.Context ctx, MouseInfo mouse){
        ctx.begin_frame();

        ctx.reset();
        ctx.start_box(0, 0);
            ctx.box_float(DrawKit.FloatMode.NONE);

            ctx.start_box(0, 0);
                ctx.box_float(DrawKit.FloatMode.LEFT);
                ctx.box_set_gap(32);

                var b1 = ctx.rect(50, 50, box_normal);
                var b2 = ctx.rect(50, 50, box_normal);
                var b3 = ctx.rect(50, 50, box_normal);

            ctx.end_box();

            ctx.start_box(0, 0);
                ctx.box_float(DrawKit.FloatMode.LEFT);
                ctx.box_set_padding(padding, padding, padding, padding);
                ctx.box_set_gap(50);

                ctx.texture(fedora_tex, 32, 32);
                ctx.texture(fedora_tex, 32, 32);
                ctx.texture(fedora_tex, 32, 32);
            ctx.end_box();

        ctx.end_box();
        DrawKit.Context.evaluate_positions(ctx.node_mngr.root,0,0);
        ctx.hitbox_query((int)mouse.mouse_x, (int)mouse.mouse_y);

        if(b1.hovered) b1.data.color.a = 1;
        if(b2.hovered) b2.data.color.a = 1;
        if(b3.hovered) b3.data.color.a = 1;

        ctx.draw(0,0);
        ctx.end_frame();
    }
}