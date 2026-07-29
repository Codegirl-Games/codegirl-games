package engine

import "core:fmt"
import sdl "vendor:sdl3"

App :: struct {
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
}

init :: proc(app: ^App, title: cstring, width, height: i32) -> bool {
	if !sdl.Init({.VIDEO}) {
		fmt.eprintfln("SDL_Init failed: %s", sdl.GetError())
		return false
	}

	if !sdl.CreateWindowAndRenderer(title, width, height, {}, &app.window, &app.renderer) {
		fmt.eprintfln("CreateWindowAndRenderer failed: %s", sdl.GetError())
		return false
	}

	return true
}

shutdown :: proc(app: ^App) {
	if app.renderer != nil do sdl.DestroyRenderer(app.renderer)
	if app.window != nil do sdl.DestroyWindow(app.window)

	sdl.Quit()
	app^ = {}
}

pump_events :: proc() -> bool {
	event: sdl.Event

	for sdl.PollEvent(&event) {
		if event.type == .QUIT {
			return false
		}
	}

	return true
}

begin_frame :: proc(app: ^App, r: u8 = 30, g: u8 = 30, b: u8 = 40, a: u8 = 255) {
	sdl.SetRenderDrawColor(app.renderer, r, g, b, a)
	sdl.RenderClear(app.renderer)
}

end_frame :: proc(app: ^App) {
	sdl.RenderPresent(app.renderer)
}

renderer :: proc(app: ^App) -> ^sdl.Renderer {
	return app.renderer
}
