package main

import "core:fmt"
import eng "pkg:engine"
import sdl "vendor:sdl3"

PERF_SPRITES      :: #config(PERF_SPRITES, 128)
PERF_FRAMES       :: #config(PERF_FRAMES, 400)
PERF_WARMUP_FRAMES :: #config(PERF_WARMUP_FRAMES, 100)
PERF_TRIALS       :: #config(PERF_TRIALS, 10)
PERF_SCENARIO     :: #config(PERF_SCENARIO, 0)
PERF_WIDTH        :: #config(PERF_WIDTH, 800)
PERF_HEIGHT       :: #config(PERF_HEIGHT, 600)

Scenario :: enum {
	Visible,
	Half_Offscreen,
	Alternating_Textures,
	Stacked,
}

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
scenario_name :: proc(scenario: Scenario) -> string {
	switch scenario {
	case .Visible:
		return "visible"
	case .Half_Offscreen:
		return "half_offscreen"
	case .Alternating_Textures:
		return "alternating_textures"
	case .Stacked:
		return "stacked"
	}
	return "unknown"
}

@(private)
present_mode_name :: proc(app: ^eng.App) -> string {
	if sdl.WindowSupportsGPUPresentMode(app.device, app.window, .IMMEDIATE) {
		return "immediate"
	}
	if sdl.WindowSupportsGPUPresentMode(app.device, app.window, .MAILBOX) {
		return "mailbox"
	}
	return "vsync"
}

@(private)
draw_frame :: proc(app: ^eng.App, sprites: []eng.Sprite) {
	for &sprite in sprites {
		eng.update_sprite(&sprite, 1.0 / 60.0)
	}

	eng.begin_frame(app)
	for &sprite in sprites {
		eng.draw_sprite(app, &sprite)
	}
	eng.end_frame(app)
}

main :: proc() {
	#assert(PERF_SPRITES > 0)
	#assert(PERF_SPRITES <= eng.MAX_SPRITES)
	#assert(PERF_FRAMES > 0)
	#assert(PERF_WARMUP_FRAMES > 0)
	#assert(PERF_TRIALS > 0)
	#assert(PERF_SCENARIO >= 0 && PERF_SCENARIO <= 3)
	#assert(PERF_WIDTH > 0)
	#assert(PERF_HEIGHT > 0)

	scenario := Scenario(PERF_SCENARIO)

	app: eng.App
	if !eng.init(&app, "sprite frame benchmark", PERF_WIDTH, PERF_HEIGHT) {
		return
	}
	defer eng.shutdown(&app)

	path := "assets_baked/characters/toad/toad.char.json"
	data_a, ok := eng.load_character_data(&app, path)
	if !ok do return
	defer eng.destroy_character_data(&app, &data_a)

	data_b: eng.Character_Data
	data_b, ok = eng.load_character_data(&app, path)
	if !ok do return
	defer eng.destroy_character_data(&app, &data_b)

	sprites: [PERF_SPRITES]eng.Sprite
	for i in 0 ..< PERF_SPRITES {
		data := &data_a
		if scenario == .Alternating_Textures && (i & 1) == 1 {
			data = &data_b
		}

		position := eng.Vec2 {
			f32(40 + (i % 16) * 48),
			f32(120 + (i / 16) * 60),
		}
		if scenario == .Half_Offscreen && (i & 1) == 1 {
			position = {-10_000, -10_000}
		} else if scenario == .Stacked {
			position = {f32(PERF_WIDTH / 2), f32(PERF_HEIGHT / 2)}
		}
		sprites[i] = eng.spawn_sprite(data, position, "walk", i % 17)
	}

	for _ in 0 ..< PERF_WARMUP_FRAMES {
		draw_frame(&app, sprites[:])
	}
	if !sdl.WaitForGPUIdle(app.device) {
		fmt.eprintfln("GPU wait failed after warm-up: %s", sdl.GetError())
		return
	}

	fmt.printfln(
		"benchmark=sprite_frame scenario=%s sprites=%d resolution=%dx%d frames=%d warmup=%d trials=%d backend=%v driver=%s present=%s",
		scenario_name(scenario),
		PERF_SPRITES,
		PERF_WIDTH,
		PERF_HEIGHT,
		PERF_FRAMES,
		PERF_WARMUP_FRAMES,
		PERF_TRIALS,
		app.shader.backend,
		sdl.GetGPUDeviceDriver(app.device),
		present_mode_name(&app),
	)

	samples: [PERF_TRIALS]f64
	for trial in 0 ..< PERF_TRIALS {
		start := sdl.GetTicksNS()
		for _ in 0 ..< PERF_FRAMES {
			draw_frame(&app, sprites[:])
		}
		if !sdl.WaitForGPUIdle(app.device) {
			fmt.eprintfln("GPU wait failed after trial %d: %s", trial + 1, sdl.GetError())
			return
		}
		elapsed := sdl.GetTicksNS() - start
		samples[trial] = f64(elapsed) / f64(PERF_FRAMES) / 1_000_000.0
		fmt.printfln(
			"trial=%d ms_per_frame=%.3f fps=%.1f",
			trial + 1,
			samples[trial],
			1_000.0 / samples[trial],
		)
	}

	median_ms := median(samples[:])
	fmt.printfln(
		"median_ms_per_frame=%.3f median_fps=%.1f",
		median_ms,
		1_000.0 / median_ms,
	)
}
