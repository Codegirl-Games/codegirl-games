package engine

import sdl "vendor:sdl3"

Key :: enum {
	A,
	D,
	Left,
	Right,
	Up,
	Down,
	Space,
	N1,
	N2,
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
	case .Up:
		scan_code = .UP
	case .Down:
		scan_code = .DOWN
	case .Space:
		scan_code = .SPACE
	case .N1:
		scan_code = ._1
	case .N2:
		scan_code = ._2
	}
	return keys[scan_code]
}
