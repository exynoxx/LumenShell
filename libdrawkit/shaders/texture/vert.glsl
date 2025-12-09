R"(
    attribute vec2 position;
    attribute vec2 texCoord;
    uniform mat4 projections[%d];
    varying vec2 fragCoord;
    void main() {
        fragCoord = texCoord;
        gl_Position = %s * vec4(position, 0.0, 1.0);
    }
)"