package main

import eng "pkg:engine"

// Minimal: load one baked character and draw idle. No input, no camera follow.
main :: proc() {
	app: eng.App
	if !eng.init(&app, "hello sprite", 800, 600) do return
	defer eng.shutdown(&app)

	data, ok := eng.load_character_data(&app, "assets_baked/characters/toad/toad.char.json")
	if !ok do return
	defer eng.destroy_character_data(&app, &data)

	sprite := eng.spawn_sprite(&data, {400, 500}, "idle", 0)

	// Screen-centered framing without gameplay camera follow:
	// treat spawn position as world; look slightly above feet.
	app.camera.position = sprite.position - {0, 100}

	last := eng.now_seconds()

	for eng.events() {
		now := eng.now_seconds()
		dt := f32(now - last)
		last = now

		eng.update_sprite(&sprite, dt)

		eng.begin_frame(&app)
		eng.draw_sprite(&app, &sprite)
		eng.end_frame(&app)
	}
}
