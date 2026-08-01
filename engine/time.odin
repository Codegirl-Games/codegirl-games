package engine

import sdl "vendor:sdl3"

// now_seconds returns seconds since SDL init (monotonic for frame timing).
now_seconds :: proc() -> f64 {
	return f64(sdl.GetTicksNS()) / 1_000_000_000.0
}
