#include <gtk/gtk.h>
#include <gtk4-layer-shell.h>
#include <math.h>

typedef struct {
    GtkWidget *window;
    GtkWidget *drawing_area;
    double animation_progress;
    guint timer_id;
} BarData;

// Custom widget that uses snapshot
#define BAR_TYPE_WIDGET (bar_widget_get_type())
G_DECLARE_FINAL_TYPE(BarWidget, bar_widget, BAR, WIDGET, GtkWidget)

struct _BarWidget {
    GtkWidget parent_instance;
    double animation_progress;
};

G_DEFINE_TYPE(BarWidget, bar_widget, GTK_TYPE_WIDGET)

static void
bar_widget_snapshot(GtkWidget *widget, GtkSnapshot *snapshot)
{
    BarWidget *self = BAR_WIDGET(widget);
    int width = gtk_widget_get_width(widget);
    int height = gtk_widget_get_height(widget);
    
    // Create a rounded rectangle path
    GskRoundedRect rounded_rect;
    graphene_rect_t rect = GRAPHENE_RECT_INIT(10, 10, width - 20, height - 20);
    graphene_size_t corner_size = GRAPHENE_SIZE_INIT(15, 15);
    
    gsk_rounded_rect_init(&rounded_rect, &rect,
                          &corner_size, &corner_size,
                          &corner_size, &corner_size);
    
    // Push rounded clip
    gtk_snapshot_push_rounded_clip(snapshot, &rounded_rect);
    
    // Draw gradient background
    GdkRGBA start_color = {0.2, 0.4, 0.8, 0.9};
    GdkRGBA end_color = {0.6, 0.2, 0.8, 0.9};
    
    graphene_point_t start_point = GRAPHENE_POINT_INIT(0, 0);
    graphene_point_t end_point = GRAPHENE_POINT_INIT(width, 0);
    
    GskColorStop stops[2] = {
        {0.0, start_color},
        {1.0, end_color}
    };
    
    gtk_snapshot_append_linear_gradient(snapshot, &rect, &start_point, &end_point, stops, 2);
    
    // Draw animated circle
    float circle_x = 50 + (width - 100) * self->animation_progress;
    float circle_y = height / 2.0;
    float radius = 20;
    
    graphene_rect_t circle_rect = GRAPHENE_RECT_INIT(
        circle_x - radius, circle_y - radius,
        radius * 2, radius * 2
    );
    
    GdkRGBA circle_color = {1.0, 1.0, 0.3, 1.0};
    GskRoundedRect circle_rounded;
    graphene_size_t circle_corner = GRAPHENE_SIZE_INIT(radius, radius);
    
    gsk_rounded_rect_init(&circle_rounded, &circle_rect,
                          &circle_corner, &circle_corner,
                          &circle_corner, &circle_corner);
    
    gtk_snapshot_push_rounded_clip(snapshot, &circle_rounded);
    gtk_snapshot_append_color(snapshot, &circle_color, &circle_rect);
    gtk_snapshot_pop(snapshot);
    
    // Pop the rounded clip
    gtk_snapshot_pop(snapshot);
    
    // Draw some text
    PangoLayout *layout = gtk_widget_create_pango_layout(widget, "GTK4 Snapshot Demo");
    PangoFontDescription *desc = pango_font_description_from_string("Sans Bold 14");
    pango_layout_set_font_description(layout, desc);
    pango_font_description_free(desc);
    
    graphene_point_t text_point = GRAPHENE_POINT_INIT(width / 2 - 100, height / 2 - 10);
    GdkRGBA text_color = {1.0, 1.0, 1.0, 1.0};
    
    gtk_snapshot_save(snapshot);
    gtk_snapshot_translate(snapshot, &text_point);
    gtk_snapshot_append_layout(snapshot, layout, &text_color);
    gtk_snapshot_restore(snapshot);
    
    g_object_unref(layout);
}

static void
bar_widget_class_init(BarWidgetClass *klass)
{
    GtkWidgetClass *widget_class = GTK_WIDGET_CLASS(klass);
    widget_class->snapshot = bar_widget_snapshot;
}

static void
bar_widget_init(BarWidget *self)
{
    self->animation_progress = 0.0;
}

static GtkWidget *
bar_widget_new(void)
{
    return g_object_new(BAR_TYPE_WIDGET, NULL);
}

// Animation timer callback
static gboolean
animate_callback(gpointer user_data)
{
    BarData *data = user_data;
    BarWidget *widget = BAR_WIDGET(data->drawing_area);
    
    widget->animation_progress += 0.02;
    if (widget->animation_progress > 1.0) {
        widget->animation_progress = 0.0;
    }
    
    gtk_widget_queue_draw(data->drawing_area);
    return G_SOURCE_CONTINUE;
}

static void
activate(GtkApplication *app, gpointer user_data)
{
    BarData *data = g_new0(BarData, 1);
    data->animation_progress = 0.0;
    
    // Create window
    data->window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(data->window), "GTK4 Layer Shell Bar");
    gtk_window_set_default_size(GTK_WINDOW(data->window), 1920, 40);
    
    // Initialize layer shell
    gtk_layer_init_for_window(GTK_WINDOW(data->window));
    
    // Configure as a top bar
    gtk_layer_set_layer(GTK_WINDOW(data->window), GTK_LAYER_SHELL_LAYER_TOP);
    gtk_layer_set_anchor(GTK_WINDOW(data->window), GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(data->window), GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(data->window), GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
    
    gtk_layer_set_exclusive_zone(GTK_WINDOW(data->window), 40);
    
    // Create our custom widget that uses snapshot
    data->drawing_area = bar_widget_new();
    
    gtk_window_set_child(GTK_WINDOW(data->window), data->drawing_area);
    
    // Start animation timer
    data->timer_id = g_timeout_add(33, animate_callback, data);
    
    gtk_window_present(GTK_WINDOW(data->window));
}

int
main(int argc, char **argv)
{
    GtkApplication *app = gtk_application_new("com.example.gtk4bar",
                                               G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    
    return status;
}