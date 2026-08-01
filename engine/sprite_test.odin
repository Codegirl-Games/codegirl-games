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

@(test)
sprite_quad_origin_feet :: proc(t: ^testing.T) {
	o := sprite_quad_origin({400, 500}, {100, 200}, {0.5, 1.0})
	testing.expect_value(t, o.x, f32(350))
	testing.expect_value(t, o.y, f32(300))
}

@(test)
sprite_quad_origin_center :: proc(t: ^testing.T) {
	o := sprite_quad_origin({400, 500}, {100, 200}, {0.5, 0.5})
	testing.expect_value(t, o.x, f32(350))
	testing.expect_value(t, o.y, f32(400))
}
