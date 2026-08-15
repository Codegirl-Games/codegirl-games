package main

import "core:fmt"
import eng "pkg:engine"

// Stress the draw budget: one Character_Data, MAX_SPRITES instances.
COUNT :: eng.MAX_SPRITES
COLS :: 16
FRAME_LOG_EVERY :: 60

main :: proc() {
	app: eng.App
	if !eng.init(&app, "crowd", 800, 600) do return
	defer eng.shutdown(&app)

	data, ok := eng.load_character_data(&app, "assets_baked/characters/toad/toad.char.json")
	if !ok do return
	defer eng.destroy_character_data(&app, &data)

	sprites: [COUNT]eng.Sprite
	for i in 0 ..< COUNT {
		col := i % COLS
		row := i / COLS
		pos := eng.Vec2 {
			f32(40 + col * 48),
			f32(80 + row * 60),
		}
		clip := "idle" if (i % 2) == 0 else "walk"
		sprites[i] = eng.spawn_sprite(&data, pos, clip, i % 5)
	}

	app.camera.position = {400, 400}

	last := eng.now_seconds()
	frame_i := 0
	sum_ms: f64
	peak_ms: f64

	for eng.events() {
		now := eng.now_seconds()
		dt := f32(now - last)
		last = now
		frame_ms := f64(dt) * 1000.0
		sum_ms += frame_ms
		if frame_ms > peak_ms do peak_ms = frame_ms
		frame_i += 1

		if frame_i % FRAME_LOG_EVERY == 0 {
			avg := sum_ms / f64(FRAME_LOG_EVERY)
			fps := 1000.0 / avg if avg > 0 else 0
			fmt.printfln(
				"crowd frame: avg=%.2f ms (%.1f FPS) peak=%.2f ms over %d frames",
				avg,
				fps,
				peak_ms,
				FRAME_LOG_EVERY,
			)
			sum_ms = 0
			peak_ms = 0
		}

		for &s in sprites {
			eng.update_sprite(&s, dt)
		}

		eng.begin_frame(&app)
		for &s in sprites {
			eng.draw_sprite(&app, &s)
		}
		eng.end_frame(&app)
	}
}
