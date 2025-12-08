#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "structures.h"
#include "shaders.h"

static const char* rounded_frag_src =
    #include "shaders/rounded/frag.glsl"
    "";

static const char* rounded_vert2_src =
    #include "shaders/rounded/vert2.glsl"
    "";

static const char* rounded_vert_src =
    #include "shaders/rounded/vert.glsl"
    "";

static const char* texture_vert_src =
    #include "shaders/texture/vert.glsl"
    "";

static const char* texture_frag_src =
    #include "shaders/texture/frag.glsl"
    "";

static const char* text_vert_src =
    #include "shaders/text/vert.glsl"
    "";

static const char* text_frag_src =
    #include "shaders/text/frag.glsl"
    "";

char* gen_vertex_shader(int num_projections) {
    int n = num_projections;
    // Calculate the size needed for the projection chain
    // Format: "projections[0] * projections[1] * ... * projections[n-1]"
    int chain_len = 0;
    for (int i = 0; i < n; i++) {
        int digits = snprintf(NULL, 0, "%d", i);
        chain_len += 13 + digits; // "projections[" + digits + "]"
        if (i < n - 1) {
            chain_len += 3; // " * "
        }
    }
    
    // Build projection chain
    char* chain = (char*)malloc(chain_len + 1);
    if (!chain) {
        return NULL;
    }
    
    char* pos = chain;
    for (int i = 0; i < n; i++) {
        pos += sprintf(pos, "projections[%d]", i);
        if (i < n - 1) {
            pos += sprintf(pos, " * ");
        }
    }
    
    // Format the complete shader
    const char* shader_template = 
        "#version 100\n"
        "    attribute vec2 position;\n"
        "    uniform mat4 projections[%d];\n"
        "    varying vec2 fragCoord;\n"
        "    void main() {\n"
        "        fragCoord = position;\n"
        "        gl_Position = %s * vec4(position, 0.0, 1.0);\n"
        "    }\n";
    
    // Calculate size needed for final output
    int size = snprintf(NULL, 0, shader_template, n, chain) + 1;
    char* output = (char*)malloc(size);
    if (!output) {
        free(chain);
        return NULL;
    }
    
    sprintf(output, shader_template, n, chain);
    free(chain);
    
    return output;
}


// Helper function to compile shader
static GLuint compile_shader(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    
    GLint success;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        char log[512];
        glGetShaderInfoLog(shader, 512, NULL, log);
        fprintf(stderr, "Shader compilation failed: %s\n", log);
        return 0;
    }
    
    return shader;
}

// Helper function to create shader program
static GLuint create_program(const char *vs_source, const char *fs_source) {
    GLuint vs = compile_shader(GL_VERTEX_SHADER, vs_source);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, fs_source);
    
    if (!vs || !fs) return 0;
    
    GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);
    
    GLint success;
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (!success) {
        char log[512];
        glGetProgramInfoLog(program, 512, NULL, log);
        fprintf(stderr, "Program linking failed: %s\n", log);
        return 0;
    }
    
    glDeleteShader(vs);
    glDeleteShader(fs);
    
    return program;
}

void init_shaders(dk_context *ctx, int num_projections){
    char *vert = gen_vertex_shader(num_projections);

    ctx->rounded_rect_program = create_program(vert, rounded_frag_src);
    ctx->texture_program = create_program(texture_vert_src, texture_frag_src);
    ctx->text_program = create_program(text_vert_src, text_frag_src);
    
    if (!ctx->rounded_rect_program  || !ctx->texture_program || !ctx->text_program) {
        fprintf(stderr, "Failed to create shader programs\n");
        return;
    }

    free(vert);
}