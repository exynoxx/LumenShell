R"(
    #version 100
    attribute vec2 position;
    uniform mat4 projection;
    varying vec2 fragCoord;
    void main() {
        fragCoord = position;
        gl_Position = projection * vec4(position, 0.0, 1.0);
    }
)"