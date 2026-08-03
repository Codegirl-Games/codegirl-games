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
