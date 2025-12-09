project('drawkit', 'c',
  version : '1.0'
)

freetype_dep = dependency('freetype2', required: true)

sources = [
  'backend.c',
  'nanosvg.c',
  'structures.c',
  'texture.c',
  'shaders.c',
  'font.c'
]

drawkit = static_library(
  'drawkit',
  sources,
  dependencies: [freetype_dep],
  include_directories: include_directories('.'),
  pic: true
)

drawkit_dep = declare_dependency(
  link_with: drawkit,
  include_directories: include_directories('.')
)
