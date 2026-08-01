.PHONY: shaders-vulkan shaders-d3d12 shaders-metal shaders-all toad check test help

help:
	@echo "Targets:"
	@echo "  shaders-vulkan  Compile SPIR-V into shaders/vulkan/"
	@echo "  shaders-d3d12   Compile DXIL into shaders/d3d12/ (needs shadercross)"
	@echo "  shaders-metal   Compile MSL into shaders/metal/ (needs shadercross)"
	@echo "  shaders-all     Build all shader backends"
	@echo "  test            Run engine unit tests"
	@echo "  check           Typecheck examples/toad"
	@echo "  toad            Run the toad example"

shaders-vulkan:
	./scripts/shaders_vulkan.sh

shaders-d3d12:
	./scripts/shaders_d3d12.sh

shaders-metal:
	./scripts/shaders_metal.sh

shaders-all: shaders-vulkan shaders-d3d12 shaders-metal

test:
	odin test engine

check:
	odin check examples/toad -collection:pkg=.

toad:
	odin run examples/toad -collection:pkg=.
