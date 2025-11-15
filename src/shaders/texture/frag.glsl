R"(#version 100
    precision mediump float;
    varying vec2 vTexCoord;
    uniform sampler2D texture0;
    uniform vec4 color;
    void main() {
        gl_FragColor = texture2D(texture0, vTexCoord) * color;
    }
)"