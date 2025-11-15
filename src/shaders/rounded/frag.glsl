#version 100
precision mediump float;
uniform vec4 color;
uniform vec4 rect; // x, y, width, height
uniform float radius;
varying vec2 fragCoord;

float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    // Calculate center of the rectangle
    vec2 center = rect.xy + rect.zw * 0.5;
    
    // Position relative to center
    vec2 p = fragCoord - center;
    
    // Half-size of rectangle
    vec2 halfSize = rect.zw * 0.5;
    
    // Calculate signed distance
    float dist = sdRoundedBox(p, halfSize, radius);
    
    // Anti-aliasing
    float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
    
    gl_FragColor = vec4(color.rgb, color.a * alpha);
}