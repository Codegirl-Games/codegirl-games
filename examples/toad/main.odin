package main

import eng "pkg:engine"

main :: proc() {
	app: eng.App
	if !eng.init(&app, "toad game", 800, 600) do return
	defer eng.shutdown(&app)

	data, ok := eng.load_character_data(&app, "assets_baked/characters/toad/toad.char.json")
	if !ok do return

	defer eng.destroy_character_data(&app, &data)

	toad := eng.spawn_sprite(&data, {400, 500}, "idle", 0)
	toad1 := eng.spawn_sprite(&data, {250, 500}, "idle", 0)
	toad2 := eng.spawn_sprite(&data, {550, 500}, "idle", 0)

	last := eng.now_seconds()
	SPEED :: f32(200)

	for eng.events() {
		now := eng.now_seconds()
		dt := f32(now - last)
		last = now

		left := eng.key_down(.A) || eng.key_down(.Left)
		right := eng.key_down(.D) || eng.key_down(.Right)

		if left || right {
			eng.set_sprite_clip(&toad, "walk")
			if left {
				toad.position.x -= SPEED * dt
				toad.flip_x = true
			}

			if right {
				toad.position.x += SPEED * dt
				toad.flip_x = false
			}
		} else {
			eng.set_sprite_clip(&toad, "idle")
		}
		eng.update_sprite(&toad, dt)

		eng.begin_frame(&app)
		eng.draw_sprite(&app, &toad)
		eng.draw_sprite(&app, &toad1)
		eng.draw_sprite(&app, &toad2)
		eng.end_frame(&app)
	}
}
