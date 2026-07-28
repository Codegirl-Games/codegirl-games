package main

import "core:fmt"
import sdl "vendor:sdl3"

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
		sdl.RenderPresent(renderer)
	}
}
