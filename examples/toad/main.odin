package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:text/regex/virtual_machine"
import sdl "vendor:sdl3"

Frame_Def :: struct {
	rect:        [4]int,
	source_size: [2]int,
	trim_offset: [2]int,
}

Clip_Def :: struct {
	loop:   bool,
	fps:    f32,
	frames: []Frame_Def,
}

Char_Def :: struct {
	version:         int,
	id:              string,
	atlas:           string,
	pixels_per_unit: f32,
	pivot:           [2]f32,
	clips:           map[string]Clip_Def,
}

main :: proc() {
	if !sdl.Init({.VIDEO}) {
		fmt.eprintfln("SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	window: ^sdl.Window
	renderer: ^sdl.Renderer

	if !sdl.CreateWindowAndRenderer("toad", 800, 600, {}, &window, &renderer) {
		fmt.eprintfln("CreateWindowAndRenderer failed: %s", sdl.GetError())
		return
	}

	defer sdl.DestroyRenderer(renderer)
	defer sdl.DestroyWindow(window)

	surface := sdl.LoadPNG("assets_baked/characters/toad/toad.atlas.png")
	if surface == nil {
		fmt.eprintfln("LoadPNG failed: %s", sdl.GetError())
		return
	}
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		fmt.eprintfln("CreateTextureFromSurface failed: %s", sdl.GetError())
		return
	}
	defer sdl.DestroyTexture(texture)

	sdl.SetTextureScaleMode(texture, .NEAREST)

	char_path := "assets_baked/characters/toad/toad.char.json"
	data, read_err := os.read_entire_file(char_path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("failed to read %s: %v", char_path, read_err)
		return
	}
	defer delete(data)

	char_def: Char_Def
	if err := json.unmarshal(data, &char_def); err != nil {
		fmt.eprintfln("json unmarshal failed: %v", err)
		return
	}

	idle, ok := char_def.clips["idle"]
	if !ok || len(idle.frames) == 0 {
		fmt.eprintfln("missing idle frames")
		return
	}

	// Atlas crop for idle frame 0 — used every frame as `src`
	r := idle.frames[0].rect // [x, y, w, h]
	src := sdl.FRect {
		x = f32(r[0]),
		y = f32(r[1]),
		w = f32(r[2]),
		h = f32(r[3]),
	}

	running := true

	for running {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			if event.type == .QUIT {
				running = false
			}
		}

		sdl.SetRenderDrawColor(renderer, 30, 30, 40, 255)
		sdl.RenderClear(renderer)

		dst := sdl.FRect {
			x = 400 - src.w * 0.5,
			y = 500 - src.h,
			w = src.w,
			h = src.h,
		}

		sdl.RenderTexture(renderer, texture, &src, &dst)

		sdl.RenderPresent(renderer)
	}
}
