package main

import eng "pkg:engine"

// Many sprites sharing one Character_Data (Flyweight) — good batching demo.
COUNT :: 24

main :: proc() {
	app: eng.App
	if !eng.init(&app, "crowd", 800, 600) do return
	defer eng.shutdown(&app)

	data, ok := eng.load_character_data(&app, "assets_baked/characters/toad/toad.char.json")
	if !ok do return
	defer eng.destroy_character_data(&app, &data)

	sprites: [COUNT]eng.Sprite
	for i in 0 ..< COUNT {
		col := i % 8
		row := i / 8
		pos := eng.Vec2 {
			f32(120 + col * 80),
			f32(280 + row * 120),
		}
		clip := "idle" if (i % 2) == 0 else "walk"
		sprites[i] = eng.spawn_sprite(&data, pos, clip, i % 5)
	}

	// Look at the middle of the grid
	app.camera.position = {400, 400}

	last := eng.now_seconds()

	for eng.events() {
		now := eng.now_seconds()
		dt := f32(now - last)
		last = now

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
