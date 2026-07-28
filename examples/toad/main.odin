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
			x = 0,
			y = 0,
			w = 400,
			h = 400,
		}
		sdl.RenderTexture(renderer, texture, nil, &dst)
		sdl.RenderPresent(renderer)
	}
}
