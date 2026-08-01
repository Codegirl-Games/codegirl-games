package engine

import sdl "vendor:sdl3"

Key :: enum {
	A,
	D,
	Left,
	Right,
}

key_down :: proc(key: Key) -> bool {
	keys := sdl.GetKeyboardState(nil)
	if keys == nil do return false

	scan_code: sdl.Scancode
	switch key {
	case .A:
		scan_code = .A
	case .D:
		scan_code = .D
	case .Left:
		scan_code = .LEFT
	case .Right:
		scan_code = .RIGHT
	}
	return keys[scan_code]
}
