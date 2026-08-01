#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/shaders_vulkan.sh
./scripts/shaders_d3d12.sh
./scripts/shaders_metal.sh
