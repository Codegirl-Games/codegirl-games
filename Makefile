.PHONY: shaders-vulkan shaders-d3d12 shaders-metal shaders-all bake toad hello_sprite crowd camera_sandbox clips check test help
.PHONY: flame flame-build flame-record flame-svg flame-report flame-tools

# Flamegraph profiling (needs: pacman -S perf). Example: make flame  or  make flame FLAME_EXAMPLE=toad
FLAME_EXAMPLE ?= crowd
FLAME_BIN := $(FLAME_EXAMPLE)_perf
FLAMEGRAPH_DIR ?= tools/FlameGraph
FLAME_OUT_DIR ?= flame
# One stamp per `make` invocation so svg/jpg/report share a name.
ifndef FLAME_STAMP
FLAME_STAMP := $(shell date +%Y%m%d-%H%M%S)
endif
FLAME_PREFIX := $(FLAME_OUT_DIR)/$(FLAME_EXAMPLE)-$(FLAME_STAMP)

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
	@echo "  flame            Build+record+SVG+JPG+text report (FLAME_EXAMPLE=$(FLAME_EXAMPLE))"
	@echo "  flame-build      Debug binary only ($(FLAME_BIN))"
	@echo "  flame-record     perf record (play, then quit)"
	@echo "  flame-svg        Convert perf.data -> $(FLAME_PREFIX).svg/.jpg"
	@echo "  flame-report     Convert perf.data -> $(FLAME_PREFIX)-report.txt"

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
	odin test assetbake

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

flame-tools:
	@if [ ! -x "$(FLAMEGRAPH_DIR)/stackcollapse-perf.pl" ] || [ ! -x "$(FLAMEGRAPH_DIR)/flamegraph.pl" ]; then \
		echo "Cloning FlameGraph scripts into $(FLAMEGRAPH_DIR)..."; \
		git clone --depth 1 https://github.com/brendangregg/FlameGraph.git "$(FLAMEGRAPH_DIR)"; \
	fi

flame-build:
	odin build examples/$(FLAME_EXAMPLE) -collection:pkg=. -out:$(FLAME_BIN) -debug

flame-record: flame-build
	@echo ">>> Profiling ./$(FLAME_BIN) — play for ~10–20s under load, then quit the window."
	@echo ">>> If perf fails with permissions: sudo sysctl kernel.perf_event_paranoid=1"
	perf record -F 99 -g --call-graph dwarf -- ./$(FLAME_BIN)

flame-svg: flame-tools
	@test -f perf.data || { echo "No perf.data — run: make flame-record"; exit 1; }
	@mkdir -p "$(FLAME_OUT_DIR)"
	perf script | "$(FLAMEGRAPH_DIR)/stackcollapse-perf.pl" | "$(FLAMEGRAPH_DIR)/flamegraph.pl" > "$(FLAME_PREFIX).svg"
	magick "$(FLAME_PREFIX).svg" "$(FLAME_PREFIX).jpg"
	@echo "Wrote $(FLAME_PREFIX).svg and $(FLAME_PREFIX).jpg"

flame-report:
	@test -f perf.data || { echo "No perf.data — run: make flame-record"; exit 1; }
	@mkdir -p "$(FLAME_OUT_DIR)"
	perf report --stdio --no-children > "$(FLAME_PREFIX)-report.txt"
	@echo "Wrote $(FLAME_PREFIX)-report.txt"

flame: flame-record flame-svg flame-report
	@echo "Artifacts: $(FLAME_PREFIX).{svg,jpg} $(FLAME_PREFIX)-report.txt"
