package main

import eng "pkg:engine"

// Many sprites sharing one Character_Data (Flyweight) — good batching demo.
COUNT :: 1000
COLS :: 40
CELL_W :: 20
CELL_H :: 24
ORIGIN_X :: 20
ORIGIN_Y :: 40

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
			f32(ORIGIN_X + col * CELL_W),
			f32(ORIGIN_Y + row * CELL_H),
		}
		clip := "idle" if (i % 2) == 0 else "walk"
		sprites[i] = eng.spawn_sprite(&data, pos, clip, i % 5)
	}

	// Look at the middle of the grid
	rows := (COUNT + COLS - 1) / COLS
	app.camera.position = {
		f32(ORIGIN_X + (COLS - 1) * CELL_W / 2),
		f32(ORIGIN_Y + (rows - 1) * CELL_H / 2),
	}

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
