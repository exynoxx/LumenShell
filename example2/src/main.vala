using LayerShell;
using Graphene;

/* Graphene with EGL Demo - Core Graphics Functions
 * Compile with: valac --pkg graphene-gobject-1.0 --pkg gl --pkg egl graphene_egl_demo.vala
 */

 using Graphene;

 public class GrapheneEGLDemo {


    private unowned EGL.Display egl_display;
    private unowned EGL.Surface egl_surface;
    private unowned Wl.Display display;


     // Transformation matrices
     private Matrix projection_matrix;
     private Matrix view_matrix;
     private Matrix model_matrix;
     
     // Animation state
     private float rotation_angle = 0.0f;
     
     public GrapheneEGLDemo() {

        LayerShell.init("graphene-panel", 1920, 100, Edge.BOTTOM);
        this.egl_display = LayerShell.get_egl_display();
        this.egl_surface = LayerShell.get_egl_surface();
        this.display = LayerShell.get_wl_display();

        setup_matrices();
     }
     
     private void setup_matrices() {
         // Initialize projection matrix (perspective)
         projection_matrix = Matrix();
         projection_matrix.init_perspective(
             60.0f,      // FOV in degrees
             16.0f/9.0f, // Aspect ratio
             0.1f,       // Near plane
             100.0f      // Far plane
         );
         
         // Initialize view matrix (camera at origin looking down -Z)
         view_matrix = Matrix();
         var up = Vec3();
         var eye = Vec3();
         var center = Vec3();

         up.init(0.0f, 1.0f, 0.0f);
         eye.init( 0.0f, 0.0f, 5.0f);
         center.init( 0.0f,  0.0f, 0.0f);

         view_matrix.init_look_at(eye, center, up);
         
         // Initialize model matrix (identity)
         model_matrix = Matrix();
         model_matrix.init_identity();
     }
     
     // Update animation - call this per frame
     public void update(float delta_time) {
         rotation_angle += 45.0f * delta_time; // 45 degrees per second
         if (rotation_angle > 360.0f) {
             rotation_angle -= 360.0f;
         }
         
         update_model_matrix();
         EGL.swap_buffers(this.egl_display, this.egl_surface); 
     }
     
     private void update_model_matrix() {
         // Create rotation quaternion
         var axis = Vec3();
         axis.init(0.0f, 1.0f, 0.0f); // Y-axis
         
         var rotation_quat = Quaternion();
         rotation_quat.init_from_angle_vec3(rotation_angle, axis);
         
         // Convert to matrix
         model_matrix = rotation_quat.to_matrix();
     }
     
     // Get MVP matrix for rendering
     public Matrix get_mvp_matrix() {
         var mvp = Matrix();
         mvp.init_identity();
         
         // Multiply: Projection * View * Model
         mvp = projection_matrix.multiply(view_matrix);
         mvp = mvp.multiply(model_matrix);
         
         return mvp;
     }
     
     // Get matrix as float array for OpenGL
     public void get_matrix_as_float_array(Matrix matrix, out float[] values) {
        values = new float[16];
         // Graphene uses column-major order (OpenGL compatible)
        matrix.to_float(ref values);
     }
     
     // Transform a 3D point
     public Point3D transform_point(Point3D point) {
         var mvp = get_mvp_matrix();
         return mvp.transform_point3d(point);
     }
     
     // Ray casting example
     public void raycast_example(float screen_x, float screen_y, 
                                 float screen_width, float screen_height) {
         // Convert screen coordinates to NDC (-1 to 1)
         float ndc_x = (2.0f * screen_x) / screen_width - 1.0f;
         float ndc_y = 1.0f - (2.0f * screen_y) / screen_height;
         
         // Create ray in world space
         var ray_origin = Point3D() { x = 0.0f, y = 0.0f, z = 5.0f };
         var ray_direction = Vec3();
         
         // Simplified ray direction calculation
         ray_direction.init(ndc_x, ndc_y, -1.0f);
         var normalized_dir = ray_direction.normalize();
         
         var ray = Ray();
         ray.init(ray_origin, normalized_dir);
         
         // Test against a sphere at origin
         var sphere_center = Point3D() { x = 0.0f, y = 0.0f, z = 0.0f };
         var sphere = Sphere();
         sphere.init(sphere_center, 1.0f);
         
         float t_hit;
         var result = ray.intersect_sphere(sphere, out t_hit);
         
         if (result != RayIntersectionKind.NONE) {
             var hit_point = ray.get_position_at(t_hit);
             stdout.printf("Hit at: (%.2f, %.2f, %.2f)\n", 
                          hit_point.x, hit_point.y, hit_point.z);
         }
     }
     
     // Frustum culling check
     public bool is_visible(Point3D position, float radius) {
         var frustum = Frustum();
         frustum.init_from_matrix(projection_matrix);
         
         // Check if sphere is in frustum
         var sphere = Sphere();
         sphere.init(position, radius);
         
         return frustum.intersects_sphere(sphere);
     }
     
     // Vector operations example
     public Vec3 calculate_normal(Point3D p1, Point3D p2, Point3D p3) {
         // Convert points to vectors
         var v1 = Vec3();
         v1.init(p2.x - p1.x, p2.y - p1.y, p2.z - p1.z);
         
         var v2 = Vec3();
         v2.init(p3.x - p1.x, p3.y - p1.y, p3.z - p1.z);
         
         // Cross product
         var normal = v1.cross(v2);
         
         // Normalize
         var normalized = normal.normalize();
         return normalized;
     }
     
     // Quaternion SLERP for smooth rotation
     public Quaternion interpolate_rotation(Quaternion from, Quaternion to, float t) {
         var result = from.slerp(to, t);
         return result;
     }
     
     // Bounding box operations
     public Box create_bounding_box(Point3D[] points) {
         if (points.length == 0) {
             var box = Box();
             box.init_from_box(Box.zero());
             return box;
         }
         
         var min = points[0];
         var max = points[0];
         
         foreach (var point in points) {
             if (point.x < min.x) min.x = point.x;
             if (point.y < min.y) min.y = point.y;
             if (point.z < min.z) min.z = point.z;
             
             if (point.x > max.x) max.x = point.x;
             if (point.y > max.y) max.y = point.y;
             if (point.z > max.z) max.z = point.z;
         }
         
         var box = Box();
         box.init(min, max);
         return box;
     }
     
     // Plane intersection test
     public bool intersects_plane(Point3D point, Vec3 normal, float distance) {
         var plane = Plane();
         var vec4 = Vec4();
         plane.init_from_vec4(
            vec4.init(normal.get_x(), normal.get_y(), normal.get_z(), distance)
         );
         
         float signed_distance = plane.distance(point);
         return Math.fabsf(signed_distance) < 0.001f;
     }
     
     // Billboard matrix (always face camera)
     public Matrix create_billboard_matrix(Vec3 position) {
         var camera_pos = Vec3();
         var to_camera = Vec3();
         // Extract camera position from view matrix
         camera_pos.init(0.0f, 0.0f, 5.0f );
         // Calculate direction to camera
         to_camera = camera_pos.subtract(position);
         
         var normalized = to_camera.normalize();
         
         // Create matrix facing camera
         var billboard = Matrix();
         billboard.init_look_at(position, camera_pos, Vec3.y_axis());
         
         return billboard;
     }
     
     // Example cube vertices transformed by MVP
     public Point3D[] get_transformed_cube_vertices() {
         var mvp = get_mvp_matrix();
         
         var vertices = new Point3D[8];
        vertices[0] = Point3D() { x = -1.0f, y = -1.0f, z = -1.0f };
        vertices[1] = Point3D() { x =  1.0f, y = -1.0f, z = -1.0f };
        vertices[2] = Point3D() { x =  1.0f, y =  1.0f, z = -1.0f };
        vertices[3] = Point3D() { x = -1.0f, y =  1.0f, z = -1.0f };
        vertices[4] = Point3D() { x = -1.0f, y = -1.0f, z =  1.0f };
        vertices[5] = Point3D() { x =  1.0f, y = -1.0f, z =  1.0f };
        vertices[6] = Point3D() { x =  1.0f, y =  1.0f, z =  1.0f };
        vertices[7] = Point3D() { x = -1.0f, y =  1.0f, z =  1.0f };
         
         var transformed = new Point3D[8];
         for (int i = 0; i < 8; i++) {
             transformed[i] = mvp.transform_point3d(vertices[i]);
         }
         
         return transformed;
     }
     
     // Print matrix for debugging
     public void print_matrix(string name, Matrix matrix) {
         float[] values = new float[16];
         matrix.to_float(ref values);
         
         stdout.printf("%s:\n", name);
         for (int row = 0; row < 4; row++) {
             stdout.printf("  [");
             for (int col = 0; col < 4; col++) {
                 stdout.printf(" %7.3f", values[row + col * 4]);
             }
             stdout.printf(" ]\n");
         }
         stdout.printf("\n");
     }
 }
 
 // Example usage
 public static int main(string[] args) {
     var demo = new GrapheneEGLDemo();
     
     stdout.printf("=== Graphene EGL Demo ===\n\n");
     
     // Update animation
     demo.update(0.016f); // 16ms frame time
     
     // Get MVP matrix
     var mvp = demo.get_mvp_matrix();
     demo.print_matrix("MVP Matrix", mvp);
     
     // Transform a point
     var point = Point3D() { x = 1.0f, y = 0.0f, z = 0.0f };
     var transformed = demo.transform_point(point);
     stdout.printf("Transformed point: (%.3f, %.3f, %.3f)\n\n", 
                   transformed.x, transformed.y, transformed.z);
     
     // Calculate normal
     var p1 = Point3D() { x = 0.0f, y = 0.0f, z = 0.0f };
     var p2 = Point3D() { x = 1.0f, y = 0.0f, z = 0.0f };
     var p3 = Point3D() { x = 0.0f, y = 1.0f, z = 0.0f };
     var normal = demo.calculate_normal(p1, p2, p3);
     stdout.printf("Triangle normal: (%.3f, %.3f, %.3f)\n\n",
                   normal.get_x(), normal.get_y(), normal.get_z());
     
     // Visibility test
     var test_pos = Point3D() { x = 0.0f, y = 0.0f, z = 0.0f };
     bool visible = demo.is_visible(test_pos, 1.0f);
     stdout.printf("Object visible: %s\n", visible ? "yes" : "no");
     
     return 0;
 }