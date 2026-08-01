package main

import eng "pkg:engine"

main :: proc() {
	app: eng.App
	if !eng.init(&app, "toad", 800, 600) do return
	defer eng.shutdown(&app)

	data, ok := eng.load_character_data(&app, "assets_baked/characters/toad/toad.char.json")
	if !ok do return

	defer eng.destroy_character_data(&app, &data)

	toad := eng.spawn_sprite(&data, {400, 500}, "idle", 0)

	for eng.events() {
		eng.begin_frame(&app)
		eng.draw_sprite(&app, &toad)
		eng.end_frame(&app)
	}
}

