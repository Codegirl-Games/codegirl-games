.PHONY: shaders-vulkan shaders-d3d12 shaders-metal shaders-all bake toad hello_sprite crowd camera_sandbox clips check test help

help:
	@echo "Targets:"
	@echo "  bake             Bake all characters under content/characters/"
	@echo "  shaders-vulkan   Compile SPIR-V into shaders/vulkan/"
	@echo "  shaders-d3d12    Compile DXIL into shaders/d3d12/ (needs shadercross)"
	@echo "  shaders-metal    Compile MSL into shaders/metal/ (needs shadercross)"
	@echo "  shaders-all      Build all shader backends"
	@echo "  test             Run engine unit tests"
	@echo "  check            Typecheck all examples"
	@echo "  toad             Run the toad example (full demo)"
	@echo "  hello_sprite     Minimal load + draw"
	@echo "  crowd            Many sprites, one Character_Data"
	@echo "  camera_sandbox   Pan camera / Space toggles follow"
	@echo "  clips            Keys 1/2 switch idle/walk"

bake:
	./scripts/bake_all.sh

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
	odin check examples/hello_sprite -collection:pkg=.
	odin check examples/crowd -collection:pkg=.
	odin check examples/camera_sandbox -collection:pkg=.
	odin check examples/clips -collection:pkg=.

toad:
	odin run examples/toad -collection:pkg=.

hello_sprite:
	odin run examples/hello_sprite -collection:pkg=.

crowd:
	odin run examples/crowd -collection:pkg=.

camera_sandbox:
	odin run examples/camera_sandbox -collection:pkg=.

clips:
	odin run examples/clips -collection:pkg=.
