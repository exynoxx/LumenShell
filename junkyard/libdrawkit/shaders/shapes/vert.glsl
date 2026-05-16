R"(
    #version 100
    attribute vec2 position;
    uniform mat4 projections[%d];
    varying vec2 fragCoord;
    void main() {
        fragCoord = position;
        gl_Position = %s * vec4(position, 0.0, 1.0);
    }
)"