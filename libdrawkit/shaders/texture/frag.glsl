R"(#version 100
    precision mediump float;
    varying vec2 fragCoord;
    uniform sampler2D texture0;
    uniform vec4 color;
    uniform int mode; //0 = texture, 1 = text

    void main() {

        if(mode == 0){
            // Texture has straight alpha (stb_image / nanosvg output).
            // Premultiply before writing so GL_ONE blend is correct.
            vec4 t = texture2D(texture0, fragCoord) * color;
            gl_FragColor = vec4(t.rgb * t.a, t.a);
        } else if (mode == 1) {
            float a = texture2D(texture0, fragCoord).r; // luminance -> sample red\n    
            // premultiply color by alpha
            float fa = color.a * a;
            gl_FragColor = vec4(color.rgb * fa, fa);
        }
    }
)"