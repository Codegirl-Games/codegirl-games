package main

import "core:testing"

@(test)
opaque_bounds_inset :: proc(t: ^testing.T) {
	// 4x4, opaque 2x2 at (1,1)
	pixels := make([]u8, 4 * 4 * 4)
	defer delete(pixels)
	for y in 1 ..= 2 {
		for x in 1 ..= 2 {
			i := (y * 4 + x) * 4
			pixels[i + 3] = 255
		}
	}
	x, y, w, h := opaque_bounds_rgba(pixels, 4, 4)
	testing.expect_value(t, x, 1)
	testing.expect_value(t, y, 1)
	testing.expect_value(t, w, 2)
	testing.expect_value(t, h, 2)
}

@(test)
opaque_bounds_full :: proc(t: ^testing.T) {
	pixels := make([]u8, 2 * 2 * 4)
	defer delete(pixels)
	for i := 3; i < len(pixels); i += 4 {
		pixels[i] = 255
	}
	x, y, w, h := opaque_bounds_rgba(pixels, 2, 2)
	testing.expect_value(t, x, 0)
	testing.expect_value(t, y, 0)
	testing.expect_value(t, w, 2)
	testing.expect_value(t, h, 2)
}

@(test)
opaque_bounds_empty :: proc(t: ^testing.T) {
	pixels := make([]u8, 3 * 3 * 4)
	defer delete(pixels)
	x, y, w, h := opaque_bounds_rgba(pixels, 3, 3)
	testing.expect_value(t, x, 0)
	testing.expect_value(t, y, 0)
	testing.expect_value(t, w, 1)
	testing.expect_value(t, h, 1)
}
