package engine

import "core:testing"

make_test_character :: proc(allocator := context.allocator) -> Character_Data {
	data: Character_Data
	data.def.clips = make(map[string]Clip_Def, allocator)

	idle_frames := make([]Frame_Def, 3, allocator)
	idle_frames[0] = {
		rect = {0, 0, 10, 10},
	}
	idle_frames[1] = {
		rect = {10, 0, 10, 10},
	}
	idle_frames[2] = {
		rect = {20, 0, 10, 10},
	}
	data.def.clips["idle"] = Clip_Def {
		loop   = true,
		fps    = 10,
		frames = idle_frames,
	}

	once_frames := make([]Frame_Def, 3, allocator)
	once_frames[0] = {
		rect = {0, 10, 10, 10},
	}
	once_frames[1] = {
		rect = {10, 10, 10, 10},
	}
	once_frames[2] = {
		rect = {20, 10, 10, 10},
	}
	data.def.clips["once"] = Clip_Def {
		loop   = false,
		fps    = 10,
		frames = once_frames,
	}

	hold_frames := make([]Frame_Def, 2, allocator)
	hold_frames[0] = {
		rect = {0, 20, 10, 10},
	}
	hold_frames[1] = {
		rect = {10, 20, 10, 10},
	}
	data.def.clips["hold"] = Clip_Def {
		loop   = true,
		fps    = 0,
		frames = hold_frames,
	}

	return data
}

destroy_test_character :: proc(data: ^Character_Data) {
	if data == nil do return
	keys := make([dynamic]string, context.temp_allocator)
	for key, clip in data.def.clips {
		delete(clip.frames)
		append(&keys, key)
	}
	for key in keys {
		delete_key(&data.def.clips, key)
	}
	delete(data.def.clips)
	data^ = {}
}

@(test)
character_clip_found_and_missing :: proc(t: ^testing.T) {
	data := make_test_character()
	defer destroy_test_character(&data)

	clip, ok := character_clip(&data, "idle")
	testing.expect(t, ok)
	testing.expect_value(t, len(clip.frames), 3)
	testing.expect(t, clip.loop)
	testing.expect_value(t, clip.fps, f32(10))

	_, ok = character_clip(&data, "missing")
	testing.expect(t, !ok)

	data.def.clips["empty"] = Clip_Def {
		loop   = true,
		fps    = 10,
		frames = nil,
	}
	_, ok = character_clip(&data, "empty")
	testing.expect(t, !ok)
}

@(test)
set_sprite_clip_switch_and_guards :: proc(t: ^testing.T) {
	data := make_test_character()
	defer destroy_test_character(&data)

	sprite := spawn_sprite(&data, {0, 0}, "idle", 0)
	testing.expect_value(t, sprite.clip, "idle")

	sprite.frame = 2
	sprite.time = 0.05
	set_sprite_clip(&sprite, "once")
	testing.expect_value(t, sprite.clip, "once")
	testing.expect_value(t, sprite.frame, 0)
	testing.expect_value(t, sprite.time, f32(0))

	sprite.frame = 1
	sprite.time = 0.09
	set_sprite_clip(&sprite, "once")
	testing.expect_value(t, sprite.frame, 1)
	testing.expect_value(t, sprite.time, f32(0.09))

	set_sprite_clip(&sprite, "nope")
	testing.expect_value(t, sprite.clip, "once")
	testing.expect_value(t, sprite.frame, 1)
	testing.expect_value(t, sprite.time, f32(0.09))
}

@(test)
spawn_sprite_valid_and_invalid :: proc(t: ^testing.T) {
	data := make_test_character()
	defer destroy_test_character(&data)

	s := spawn_sprite(&data, {1, 2}, "idle", 0)
	testing.expect_value(t, s.clip, "idle")
	testing.expect_value(t, s.frame, 0)
	testing.expect_value(t, s.time, f32(0))
	testing.expect_value(t, s.position, Vec2{1, 2})

	s2 := spawn_sprite(&data, {}, "idle", 2)
	testing.expect_value(t, s2.clip, "idle")
	testing.expect_value(t, s2.frame, 2)

	s3 := spawn_sprite(&data, {}, "idle", 99)
	testing.expect_value(t, s3.frame, 2)

	bad := spawn_sprite(&data, {}, "missing", 0)
	testing.expect_value(t, bad.clip, "")
	testing.expect_value(t, bad.frame, 0)
	testing.expect_value(t, bad.time, f32(0))
}

@(test)
update_sprite_advances_one_frame :: proc(t: ^testing.T) {
	data := make_test_character()
	defer destroy_test_character(&data)

	s := spawn_sprite(&data, {}, "idle", 0)
	update_sprite(&s, 0.1)
	testing.expect_value(t, s.frame, 1)
	testing.expect_value(t, s.time, f32(0))
}

@(test)
update_sprite_advances_multiple_frames :: proc(t: ^testing.T) {
	data := make_test_character()
	defer destroy_test_character(&data)

	s := spawn_sprite(&data, {}, "idle", 0)
	update_sprite(&s, 0.25)
	testing.expect_value(t, s.frame, 2)
	testing.expect(t, s.time > 0.049 && s.time < 0.051)
}

@(test)
update_sprite_loops :: proc(t: ^testing.T) {
	data := make_test_character()
	defer destroy_test_character(&data)

	s := spawn_sprite(&data, {}, "idle", 2)
	update_sprite(&s, 0.1)
	testing.expect_value(t, s.frame, 0)
}

@(test)
update_sprite_non_loop_holds_last :: proc(t: ^testing.T) {
	data := make_test_character()
	defer destroy_test_character(&data)

	s := spawn_sprite(&data, {}, "once", 2)
	s.time = 0.05
	update_sprite(&s, 0.1)
	testing.expect_value(t, s.frame, 2)
	testing.expect_value(t, s.time, f32(0))
}

@(test)
update_sprite_fps_zero_holds :: proc(t: ^testing.T) {
	data := make_test_character()
	defer destroy_test_character(&data)

	s := spawn_sprite(&data, {}, "hold", 0)
	update_sprite(&s, 1.0)
	testing.expect_value(t, s.frame, 0)
}

@(test)
update_sprite_dt_non_positive_noop :: proc(t: ^testing.T) {
	data := make_test_character()
	defer destroy_test_character(&data)

	s := spawn_sprite(&data, {}, "idle", 0)
	update_sprite(&s, 0)
	update_sprite(&s, -0.1)
	testing.expect_value(t, s.frame, 0)
	testing.expect_value(t, s.time, f32(0))
}

@(test)
update_sprite_nil_and_missing_clip_safe :: proc(t: ^testing.T) {
	update_sprite(nil, 0.1)

	data := make_test_character()
	defer destroy_test_character(&data)

	s := Sprite {
		data  = &data,
		clip  = "missing",
		frame = 0,
		time  = 0,
	}
	update_sprite(&s, 0.1)
	testing.expect_value(t, s.frame, 0)

	s2 := Sprite {
		data = nil,
		clip = "idle",
	}
	update_sprite(&s2, 0.1)
}
