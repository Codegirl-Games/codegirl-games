package engine

import "core:testing"

@(test)
parse_char_def_happy_path :: proc(t: ^testing.T) {
	src := transmute([]u8)string(
		`{"version":1,"id":"toad","atlas":"toad.atlas.png","pixels_per_unit":160.0,"pivot":[0.5,1.0],"clips":{"idle":{"loop":true,"fps":8.0,"frames":[{"rect":[1,2,3,4],"source_size":[3,4],"trim_offset":[0,0]}]}}}`,
	)

	def, ok := parse_char_def(src)
	defer destroy_char_def(&def)

	testing.expect(t, ok)
	testing.expect_value(t, def.id, "toad")
	testing.expect_value(t, def.atlas, "toad.atlas.png")
	testing.expect_value(t, def.version, 1)
	testing.expect_value(t, def.pixels_per_unit, f32(160.0))
	testing.expect_value(t, def.pivot[0], f32(0.5))
	testing.expect_value(t, def.pivot[1], f32(1.0))

	idle, found := def.clips["idle"]
	testing.expect(t, found)
	testing.expect(t, idle.loop)
	testing.expect_value(t, idle.fps, f32(8.0))
	testing.expect_value(t, len(idle.frames), 1)
	testing.expect_value(t, idle.frames[0].rect, [4]int{1, 2, 3, 4})
}

@(test)
parse_char_def_bad_json :: proc(t: ^testing.T) {
	_, ok := parse_char_def(transmute([]u8)string("{ not json"))
	testing.expect(t, !ok)
}

@(test)
character_frame_rect_hit_and_miss :: proc(t: ^testing.T) {
	data: Character_Data
	data.def.clips = make(map[string]Clip_Def)
	defer delete(data.def.clips)

	frames := make([]Frame_Def, 2)
	frames[0] = {rect = {10, 20, 30, 40}}
	frames[1] = {rect = {50, 60, 70, 80}}
	defer delete(frames)

	data.def.clips["idle"] = Clip_Def {
		loop   = true,
		fps    = 10,
		frames = frames,
	}

	rect, ok := character_frame_rect(&data, "idle", 1)
	testing.expect(t, ok)
	testing.expect_value(t, rect, [4]int{50, 60, 70, 80})

	_, ok = character_frame_rect(&data, "missing", 0)
	testing.expect(t, !ok)

	_, ok = character_frame_rect(&data, "idle", -1)
	testing.expect(t, !ok)

	_, ok = character_frame_rect(&data, "idle", 2)
	testing.expect(t, !ok)
}

destroy_char_def :: proc(def: ^Char_Def) {
	if def == nil do return

	keys := make([dynamic]string, context.temp_allocator)
	for key, clip in def.clips {
		delete(clip.frames)
		append(&keys, key)
	}
	for key in keys {
		delete_key(&def.clips, key)
		delete(key)
	}
	delete(def.clips)
	delete(def.id)
	delete(def.atlas)
	def^ = {}
}
