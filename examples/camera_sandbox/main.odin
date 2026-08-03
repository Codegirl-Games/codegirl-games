package main

import eng "pkg:engine"

// Camera sandbox: toad stays put; arrows pan the camera. Space toggles follow mode.
main :: proc() {
	app: eng.App
	if !eng.init(&app, "camera sandbox", 800, 600) do return
	defer eng.shutdown(&app)

	data, ok := eng.load_character_data(&app, "assets_baked/characters/toad/toad.char.json")
	if !ok do return
	defer eng.destroy_character_data(&app, &data)

	toad := eng.spawn_sprite(&data, {0, 0}, "idle", 0)
	app.camera.position = {0, -100}

	follow := false
	space_was_down := false
	CAM_SPEED :: f32(300)

	last := eng.now_seconds()

	for eng.events() {
		now := eng.now_seconds()
		dt := f32(now - last)
		last = now

		space := eng.key_down(.Space)
		if space && !space_was_down {
			follow = !follow
		}
		space_was_down = space

		if follow {
			app.camera.position = toad.position - {0, 100}
		} else {
			if eng.key_down(.Left) || eng.key_down(.A) {
				app.camera.position.x -= CAM_SPEED * dt
			}
			if eng.key_down(.Right) || eng.key_down(.D) {
				app.camera.position.x += CAM_SPEED * dt
			}
			if eng.key_down(.Up) {
				app.camera.position.y -= CAM_SPEED * dt
			}
			if eng.key_down(.Down) {
				app.camera.position.y += CAM_SPEED * dt
			}
		}

		eng.update_sprite(&toad, dt)

		eng.begin_frame(&app)
		eng.draw_sprite(&app, &toad)
		eng.end_frame(&app)
	}
}
