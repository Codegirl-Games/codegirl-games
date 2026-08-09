package main

import "core:fmt"
import "core:os"
import eng "pkg:engine"
import sdl "vendor:sdl3"

PERF_ITERATIONS :: #config(PERF_ITERATIONS, 2_000_000)
PERF_WARMUP     :: #config(PERF_WARMUP, 10_000)
PERF_TRIALS     :: #config(PERF_TRIALS, 7)

@(private)
median :: proc(values: []f64) -> f64 {
	for i in 1 ..< len(values) {
		value := values[i]
		j := i
		for j > 0 {
			if values[j - 1] <= value do break
			values[j] = values[j - 1]
			j -= 1
		}
		values[j] = value
	}

	middle := len(values) / 2
	if len(values) & 1 == 1 do return values[middle]
	return (values[middle - 1] + values[middle]) / 2
}

@(private)
run_draws :: proc(app: ^eng.App, sprite: ^eng.Sprite, iterations: int) -> u64 {
	clear(&app.draw_list)
	start := sdl.GetTicksNS()
	for i in 0 ..< iterations {
		if len(app.draw_list) >= eng.MAX_SPRITES {
			clear(&app.draw_list)
		}

		// Vary an input so optimized builds cannot hoist the draw calculations.
		sprite.position.x = f32(i & 1023)
		eng.draw_sprite(app, sprite)
	}
	return sdl.GetTicksNS() - start
}

main :: proc() {
	#assert(PERF_ITERATIONS > 0)
	#assert(PERF_WARMUP > 0)
	#assert(PERF_TRIALS > 0)

	file_data, err := os.read_entire_file(
		"assets_baked/characters/toad/toad.char.json",
		context.allocator,
	)
	if err != nil {
		fmt.eprintfln("benchmark asset read failed: %v", err)
		return
	}
	defer delete(file_data)

	def, ok := eng.parse_char_def(file_data)
	if !ok do return

	data := eng.Character_Data {
		def     = def,
		texture = cast(^sdl.GPUTexture)uintptr(1),
		width   = 1911,
		height  = 1526,
	}
	app := eng.App {
		cmd               = cast(^sdl.GPUCommandBuffer)uintptr(1),
		swapchain_texture = cast(^sdl.GPUTexture)uintptr(2),
		swapchain_w       = 800,
		swapchain_h       = 600,
		camera             = eng.camera_default(),
		draw_list          = make(
			[dynamic]eng.Queued_Sprite,
			0,
			eng.MAX_SPRITES,
		),
	}
	defer delete(app.draw_list)

	sprite := eng.spawn_sprite(&data, {400, 400}, "walk", 4)
	_ = run_draws(&app, &sprite, PERF_WARMUP)

	samples: [PERF_TRIALS]f64
	fmt.printfln(
		"benchmark=draw_sprite iterations=%d warmup=%d trials=%d sprites_per_queue=%d",
		PERF_ITERATIONS,
		PERF_WARMUP,
		PERF_TRIALS,
		eng.MAX_SPRITES,
	)
	for trial in 0 ..< PERF_TRIALS {
		elapsed := run_draws(&app, &sprite, PERF_ITERATIONS)
		samples[trial] = f64(elapsed) / f64(PERF_ITERATIONS)
		fmt.printfln("trial=%d ns_per_draw=%.3f", trial + 1, samples[trial])
	}

	fmt.printfln("median_ns_per_draw=%.3f", median(samples[:]))
}
