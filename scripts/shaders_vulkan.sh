#!/usr/bin/env bash
set -euo pipefail
mkdir -p shaders/vulkan
glslangValidator -V shaders/sprite.vert.glsl -o shaders/vulkan/sprite.vert.spv
glslangValidator -V shaders/sprite.frag.glsl -o shaders/vulkan/sprite.frag.spv

