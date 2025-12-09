R"(#version 100
    precision mediump float;
    varying vec2 fragCoord;
    uniform sampler2D texture0;
    uniform vec4 color;
    uniform int mode; //0 = texture, 1 = text

    void main() {

        if(mode == 0){
            gl_FragColor = texture2D(texture0, fragCoord) * color;
        } else if (mode == 1) {
            float a = texture2D(texture0, fragCoord).r; // luminance -> sample red\n    
            // premultiply color by alpha
            gl_FragColor = vec4(color.rgb, color.a * a);
        }
    }
)"