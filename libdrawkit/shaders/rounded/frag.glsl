R"(
    #version 100
    precision mediump float;

    uniform vec4 color;       // RGBA color
    uniform vec4 rect;        // x, y, width, height (used for rect/rounded rect)
    uniform float radius;     // corner radius for rounded rect or circle radius
    uniform int mode;         // 0 = rect, 1 = rounded rect, 2 = circle

    varying vec2 fragCoord;

    // Signed distance for rounded rectangle
    float sdRoundedBox(vec2 p, vec2 b, float r) {
        vec2 q = abs(p) - b + r;
        return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
    }

    void main() {
        float alpha = 1.0;

        if (mode == 0) {
            // SOLID RECT
            alpha = 1.0;
        }
        else if (mode == 1) {
            // ROUNDED RECT
            vec2 center = rect.xy + rect.zw * 0.5;
            vec2 p = fragCoord - center;
            vec2 halfSize = rect.zw * 0.5;
            float dist = sdRoundedBox(p, halfSize, radius);
            alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
        }
        else if (mode == 2) {
            // CIRCLE
            vec2 center = rect.xy + rect.zw * 0.5;
            vec2 p = fragCoord - center;
            float dist = length(p) - radius;
            alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
        }

        gl_FragColor = vec4(color.rgb, color.a * alpha);
    }

)"