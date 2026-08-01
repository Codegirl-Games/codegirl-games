package engine

import "core:testing"

@(test)
to_clip_corners :: proc(t: ^testing.T) {
	// top-left pixel (0,0) -> clip (-1, 1) with y-flip
	p := to_clip(0, 0, 800, 600)
	testing.expect_value(t, p[0], f32(-1))
	testing.expect_value(t, p[1], f32(1))

	// bottom-right pixel (sw, sh) -> clip (1, -1)
	p = to_clip(800, 600, 800, 600)
	testing.expect_value(t, p[0], f32(1))
	testing.expect_value(t, p[1], f32(-1))

	// center
	p = to_clip(400, 300, 800, 600)
	testing.expect_value(t, p[0], f32(0))
	testing.expect_value(t, p[1], f32(0))
}
