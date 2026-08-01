#!/usr/bin/env bash
set -euo pipefail

if ! command -v shadercross >/dev/null 2>&1; then
	echo "shadercross not found (SDL_shadercross). Install it to build Metal MSL shaders." >&2
	exit 1
fi

mkdir -p shaders/metal
shadercross shaders/sprite.vert.glsl -o shaders/metal/sprite.vert.msl -s vertex -e main
shadercross shaders/sprite.frag.glsl -o shaders/metal/sprite.frag.msl -s fragment -e main
