package engine

import "core:testing"
import sdl "vendor:sdl3"

fake_tex :: proc(id: uintptr) -> ^sdl.GPUTexture {
	return cast(^sdl.GPUTexture)id
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
