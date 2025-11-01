R"(attribute vec2 position;
    attribute vec2 texCoord;
    uniform mat4 projection;
    varying vec2 vTexCoord;
    void main() {
        vTexCoord = texCoord;
        gl_Position = projection * vec4(position, 0.0, 1.0);
    }
)"