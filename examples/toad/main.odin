package main

import eng "pkg:engine"

main :: proc() {
	app: eng.App
	if !eng.init(&app, "toad example", 800, 600) {
		return
	}
	defer eng.shutdown(&app)

	data, ok := eng.load_character_data(
		app.renderer,
		"assets_baked/characters/toad/toad.char.json",
	)
	if !ok {
		return
	}
	defer eng.destroy_character_data(&data)

	toad := eng.spawn_sprite(&data, {400, 500}, "idle", 0)

	for eng.pump_events() {
		eng.begin_frame(&app)
		eng.draw_sprite(app.renderer, &toad)
		eng.end_frame(&app)
	}
}

