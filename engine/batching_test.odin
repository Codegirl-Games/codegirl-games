package engine

import "core:testing"
import sdl "vendor:sdl3"

fake_tex :: proc(id: uintptr) -> ^sdl.GPUTexture {
	return cast(^sdl.GPUTexture)id
}

queued :: proc(tex_id: uintptr, group: u32, marker: f32) -> Queued_Sprite {
	q: Queued_Sprite
	q.texture = fake_tex(tex_id)
	q.batch_group = group
	q.verts[0].pos = {marker, 0}
	return q
}

marker_of :: proc(q: Queued_Sprite) -> f32 {
	return q.verts[0].pos.x
}

@(test)
texture_run_len_empty_or_oob :: proc(t: ^testing.T) {
	testing.expect_value(t, texture_run_len(nil, 0), 0)
	list := []Queued_Sprite{}
	testing.expect_value(t, texture_run_len(list, 0), 0)
	list = make([]Queued_Sprite, 1)
	defer delete(list)
	list[0] = {texture = fake_tex(1)}
	testing.expect_value(t, texture_run_len(list, -1), 0)
	testing.expect_value(t, texture_run_len(list, 1), 0)
}

@(test)
texture_run_len_single :: proc(t: ^testing.T) {
	list := make([]Queued_Sprite, 1)
	defer delete(list)
	list[0] = {texture = fake_tex(1)}
	testing.expect_value(t, texture_run_len(list, 0), 1)
}

@(test)
texture_run_len_same_texture :: proc(t: ^testing.T) {
	tex := fake_tex(1)
	list := make([]Queued_Sprite, 3)
	defer delete(list)
	list[0] = {texture = tex}
	list[1] = {texture = tex}
	list[2] = {texture = tex}
	testing.expect_value(t, texture_run_len(list, 0), 3)
}

@(test)
texture_run_len_breaks_on_change :: proc(t: ^testing.T) {
	a := fake_tex(1)
	b := fake_tex(2)
	list := make([]Queued_Sprite, 3)
	defer delete(list)
	list[0] = {texture = a}
	list[1] = {texture = a}
	list[2] = {texture = b}
	testing.expect_value(t, texture_run_len(list, 0), 2)
	testing.expect_value(t, texture_run_len(list, 2), 1)
}

@(test)
texture_run_len_all_different :: proc(t: ^testing.T) {
	list := make([]Queued_Sprite, 3)
	defer delete(list)
	list[0] = {texture = fake_tex(1)}
	list[1] = {texture = fake_tex(2)}
	list[2] = {texture = fake_tex(3)}
	testing.expect_value(t, texture_run_len(list, 0), 1)
	testing.expect_value(t, texture_run_len(list, 1), 1)
	testing.expect_value(t, texture_run_len(list, 2), 1)
}

@(test)
group_texture_runs_strict_order_unchanged :: proc(t: ^testing.T) {
	// Group 0 alternates textures; sorting must not reorder (alpha order).
	list := []Queued_Sprite {
		queued(2, 0, 1),
		queued(1, 0, 2),
		queued(2, 0, 3),
		queued(1, 0, 4),
	}
	before_runs := texture_run_count(list)
	group_texture_runs(list)
	testing.expect_value(t, texture_run_count(list), before_runs)
	testing.expect_value(t, marker_of(list[0]), f32(1))
	testing.expect_value(t, marker_of(list[1]), f32(2))
	testing.expect_value(t, marker_of(list[2]), f32(3))
	testing.expect_value(t, marker_of(list[3]), f32(4))
}

@(test)
group_texture_runs_reduces_runs_inside_group :: proc(t: ^testing.T) {
	list := []Queued_Sprite {
		queued(2, 1, 1),
		queued(1, 1, 2),
		queued(2, 1, 3),
		queued(1, 1, 4),
	}
	testing.expect_value(t, texture_run_count(list), 4)
	group_texture_runs(list)
	testing.expect_value(t, texture_run_count(list), 2)
	testing.expect(t, list[0].texture == fake_tex(1), "lower texture pointer first")
	testing.expect(t, list[1].texture == fake_tex(1), "same texture run")
	testing.expect(t, list[2].texture == fake_tex(2), "second texture run")
	testing.expect(t, list[3].texture == fake_tex(2), "second texture run cont")
}

@(test)
group_texture_runs_stable_same_texture :: proc(t: ^testing.T) {
	list := []Queued_Sprite {
		queued(2, 1, 10),
		queued(1, 1, 20),
		queued(2, 1, 30),
		queued(1, 1, 40),
	}
	group_texture_runs(list)
	// Same-texture relative order preserved (stable sort).
	testing.expect_value(t, marker_of(list[0]), f32(20))
	testing.expect_value(t, marker_of(list[1]), f32(40))
	testing.expect_value(t, marker_of(list[2]), f32(10))
	testing.expect_value(t, marker_of(list[3]), f32(30))
}

@(test)
group_texture_runs_respects_group_boundaries :: proc(t: ^testing.T) {
	list := []Queued_Sprite {
		queued(2, 1, 1),
		queued(1, 1, 2),
		queued(2, 0, 3), // strict barrier
		queued(1, 2, 4),
		queued(2, 2, 5),
	}
	group_texture_runs(list)
	testing.expect_value(t, marker_of(list[2]), f32(3)) // barrier stays put
	testing.expect(t, list[0].texture == fake_tex(1))
	testing.expect(t, list[1].texture == fake_tex(2))
	testing.expect(t, list[3].texture == fake_tex(1))
	testing.expect(t, list[4].texture == fake_tex(2))
	testing.expect_value(t, list[0].batch_group, u32(1))
	testing.expect_value(t, list[1].batch_group, u32(1))
	testing.expect_value(t, list[2].batch_group, u32(0))
	testing.expect_value(t, list[3].batch_group, u32(2))
	testing.expect_value(t, list[4].batch_group, u32(2))
}

@(test)
group_texture_runs_does_not_merge_across_different_groups :: proc(t: ^testing.T) {
	// Adjacent nonzero groups with different ids must not merge runs across.
	list := []Queued_Sprite {
		queued(1, 1, 1),
		queued(2, 1, 2),
		queued(1, 2, 3),
		queued(2, 2, 4),
	}
	group_texture_runs(list)
	testing.expect_value(t, texture_run_count(list), 4)
	testing.expect_value(t, list[0].batch_group, u32(1))
	testing.expect_value(t, list[1].batch_group, u32(1))
	testing.expect_value(t, list[2].batch_group, u32(2))
	testing.expect_value(t, list[3].batch_group, u32(2))
}

@(test)
group_texture_runs_empty :: proc(t: ^testing.T) {
	list := []Queued_Sprite{}
	testing.expect_value(t, texture_run_count(list), 0)
	group_texture_runs(list)
	testing.expect_value(t, texture_run_count(list), 0)
}

@(test)
group_texture_runs_already_optimal :: proc(t: ^testing.T) {
	list := []Queued_Sprite {
		queued(1, 1, 10),
		queued(1, 1, 20),
		queued(2, 1, 30),
		queued(2, 1, 40),
	}
	testing.expect_value(t, texture_run_count(list), 2)
	group_texture_runs(list)
	testing.expect_value(t, texture_run_count(list), 2)
	testing.expect_value(t, marker_of(list[0]), f32(10))
	testing.expect_value(t, marker_of(list[1]), f32(20))
	testing.expect_value(t, marker_of(list[2]), f32(30))
	testing.expect_value(t, marker_of(list[3]), f32(40))
}

@(test)
group_texture_runs_alternating_many_stable :: proc(t: ^testing.T) {
	// Characterization: large alternating group must collapse to two runs
	// while preserving same-texture submission order (markers).
	N :: 64
	list := make([]Queued_Sprite, N)
	defer delete(list)
	for i in 0 ..< N {
		tex: uintptr = 2 if (i % 2) == 0 else 1
		list[i] = queued(tex, 1, f32(i + 1))
	}
	testing.expect_value(t, texture_run_count(list), N)
	group_texture_runs(list)
	testing.expect_value(t, texture_run_count(list), 2)
	testing.expect(t, list[0].texture == fake_tex(1))
	testing.expect(t, list[N / 2 - 1].texture == fake_tex(1))
	testing.expect(t, list[N / 2].texture == fake_tex(2))
	testing.expect(t, list[N - 1].texture == fake_tex(2))
	for i in 0 ..< N / 2 {
		testing.expect_value(t, marker_of(list[i]), f32(2 * i + 2)) // odd markers: 2,4,...,N
		testing.expect_value(t, marker_of(list[N / 2 + i]), f32(2 * i + 1)) // even markers: 1,3,...,N-1
	}
}

@(test)
group_texture_runs_three_textures_stable :: proc(t: ^testing.T) {
	list := []Queued_Sprite {
		queued(3, 1, 1),
		queued(1, 1, 2),
		queued(2, 1, 3),
		queued(3, 1, 4),
		queued(1, 1, 5),
		queued(2, 1, 6),
	}
	testing.expect_value(t, texture_run_count(list), 6)
	group_texture_runs(list)
	testing.expect_value(t, texture_run_count(list), 3)
	testing.expect_value(t, marker_of(list[0]), f32(2))
	testing.expect_value(t, marker_of(list[1]), f32(5))
	testing.expect_value(t, marker_of(list[2]), f32(3))
	testing.expect_value(t, marker_of(list[3]), f32(6))
	testing.expect_value(t, marker_of(list[4]), f32(1))
	testing.expect_value(t, marker_of(list[5]), f32(4))
}

@(test)
group_texture_runs_noncontiguous_same_group_id :: proc(t: ^testing.T) {
	// Same nonzero id split by group 0: each window regroups alone.
	list := []Queued_Sprite {
		queued(2, 1, 1),
		queued(1, 1, 2),
		queued(2, 0, 3),
		queued(2, 1, 4),
		queued(1, 1, 5),
	}
	group_texture_runs(list)
	testing.expect_value(t, marker_of(list[2]), f32(3))
	testing.expect(t, list[0].texture == fake_tex(1))
	testing.expect(t, list[1].texture == fake_tex(2))
	testing.expect_value(t, list[2].batch_group, u32(0))
	testing.expect(t, list[3].texture == fake_tex(1))
	testing.expect(t, list[4].texture == fake_tex(2))
	testing.expect_value(t, list[0].batch_group, u32(1))
	testing.expect_value(t, list[1].batch_group, u32(1))
	testing.expect_value(t, list[3].batch_group, u32(1))
	testing.expect_value(t, list[4].batch_group, u32(1))
}

make_test_draw_app :: proc() -> App {
	app: App
	app.cmd = cast(^sdl.GPUCommandBuffer)uintptr(1)
	app.swapchain_texture = fake_tex(99)
	app.swapchain_w = 800
	app.swapchain_h = 600
	app.camera = camera_default()
	app.draw_list = make([dynamic]Queued_Sprite)
	return app
}

destroy_test_draw_app :: proc(app: ^App) {
	if app == nil do return
	delete(app.draw_list)
	app^ = {}
}

make_test_draw_character :: proc() -> Character_Data {
	data: Character_Data
	data.texture = fake_tex(42)
	data.width = 100
	data.height = 100
	data.def.pivot = {0.5, 1.0}
	data.def.clips = make(map[string]Clip_Def)
	frames := make([]Frame_Def, 1)
	frames[0] = Frame_Def {
		rect        = {0, 0, 10, 10},
		source_size = {10, 10},
		trim_offset = {0, 0},
	}
	data.def.clips["idle"] = Clip_Def {
		loop   = true,
		fps    = 10,
		frames = frames,
	}
	return data
}

destroy_test_draw_character :: proc(data: ^Character_Data) {
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
draw_sprite_stamps_batch_group_zero :: proc(t: ^testing.T) {
	app := make_test_draw_app()
	defer destroy_test_draw_app(&app)
	data := make_test_draw_character()
	defer destroy_test_draw_character(&data)

	sprite := spawn_sprite(&data, {100, 200}, "idle", 0)
	draw_sprite(&app, &sprite)

	testing.expect_value(t, len(app.draw_list), 1)
	testing.expect_value(t, app.draw_list[0].batch_group, u32(0))
	testing.expect(t, app.draw_list[0].texture == data.texture)
}

@(test)
draw_sprite_at_max_sprites_does_not_append :: proc(t: ^testing.T) {
	app := make_test_draw_app()
	defer destroy_test_draw_app(&app)
	data := make_test_draw_character()
	defer destroy_test_draw_character(&data)

	for _ in 0 ..< MAX_SPRITES {
		append(&app.draw_list, Queued_Sprite{texture = data.texture})
	}
	testing.expect_value(t, len(app.draw_list), MAX_SPRITES)

	sprite := spawn_sprite(&data, {100, 200}, "idle", 0)
	draw_sprite(&app, &sprite)

	testing.expect_value(t, len(app.draw_list), MAX_SPRITES)
}

@(test)
draw_sprite_batched_stamps_batch_group :: proc(t: ^testing.T) {
	app := make_test_draw_app()
	defer destroy_test_draw_app(&app)
	data := make_test_draw_character()
	defer destroy_test_draw_character(&data)

	sprite := spawn_sprite(&data, {100, 200}, "idle", 0)
	draw_sprite_batched(&app, &sprite, 7)

	testing.expect_value(t, len(app.draw_list), 1)
	testing.expect_value(t, app.draw_list[0].batch_group, u32(7))
	testing.expect(t, app.draw_list[0].texture == data.texture)
}

@(test)
draw_sprite_batched_guards_leave_list_unchanged :: proc(t: ^testing.T) {
	app := make_test_draw_app()
	defer destroy_test_draw_app(&app)
	data := make_test_draw_character()
	defer destroy_test_draw_character(&data)
	sprite := spawn_sprite(&data, {100, 200}, "idle", 0)

	app.cmd = nil
	draw_sprite_batched(&app, &sprite, 1)
	testing.expect_value(t, len(app.draw_list), 0)
	app.cmd = cast(^sdl.GPUCommandBuffer)uintptr(1)

	app.swapchain_texture = nil
	draw_sprite_batched(&app, &sprite, 1)
	testing.expect_value(t, len(app.draw_list), 0)
	app.swapchain_texture = fake_tex(99)

	draw_sprite_batched(&app, nil, 1)
	testing.expect_value(t, len(app.draw_list), 0)

	no_data := sprite
	no_data.data = nil
	draw_sprite_batched(&app, &no_data, 1)
	testing.expect_value(t, len(app.draw_list), 0)

	no_tex := sprite
	tex_data := data
	tex_data.texture = nil
	no_tex.data = &tex_data
	draw_sprite_batched(&app, &no_tex, 1)
	testing.expect_value(t, len(app.draw_list), 0)
}

@(test)
prepare_draw_batches_regroups_then_plans_runs :: proc(t: ^testing.T) {
	list := []Queued_Sprite {
		queued(2, 1, 1),
		queued(1, 1, 2),
		queued(2, 1, 3),
		queued(1, 1, 4),
		queued(3, 0, 5),
		queued(1, 0, 6),
	}
	batches := make([dynamic]Draw_Batch)
	defer delete(batches)

	prepare_draw_batches(list, &batches)

	testing.expect_value(t, len(batches), 4)
	testing.expect_value(t, batches[0].start, 0)
	testing.expect_value(t, batches[0].count, 2)
	testing.expect(t, batches[0].texture == fake_tex(1))
	testing.expect_value(t, batches[1].start, 2)
	testing.expect_value(t, batches[1].count, 2)
	testing.expect(t, batches[1].texture == fake_tex(2))
	testing.expect_value(t, batches[2].start, 4)
	testing.expect_value(t, batches[2].count, 1)
	testing.expect(t, batches[2].texture == fake_tex(3))
	testing.expect_value(t, batches[3].start, 5)
	testing.expect_value(t, batches[3].count, 1)
	testing.expect(t, batches[3].texture == fake_tex(1))

	// Group 0 submission order preserved.
	testing.expect_value(t, marker_of(list[4]), f32(5))
	testing.expect_value(t, marker_of(list[5]), f32(6))
	testing.expect_value(t, list[4].batch_group, u32(0))
	testing.expect_value(t, list[5].batch_group, u32(0))
}
