#!/usr/bin/env bash
set -euo pipefail

if ! command -v shadercross >/dev/null 2>&1; then
	echo "shadercross not found (SDL_shadercross). Install it to build D3D12 DXIL shaders." >&2
	exit 1
fi

mkdir -p shaders/d3d12
shadercross shaders/sprite.vert.glsl -o shaders/d3d12/sprite.vert.dxil -s vertex -e main
shadercross shaders/sprite.frag.glsl -o shaders/d3d12/sprite.frag.dxil -s fragment -e main
