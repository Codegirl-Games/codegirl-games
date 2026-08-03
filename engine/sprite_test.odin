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

@(test)
frame_uvs_unflipped :: proc(t: ^testing.T) {
	u0, v0, u1, v1 := frame_uvs({10, 20, 30, 40}, 100, 200, false)
	testing.expect_value(t, u0, f32(0.1))
	testing.expect_value(t, v0, f32(0.1))
	testing.expect_value(t, u1, f32(0.4))
	testing.expect_value(t, v1, f32(0.3))
	testing.expect(t, u0 < u1, "unflipped UVs should have u0 < u1")
}

@(test)
frame_uvs_flipped :: proc(t: ^testing.T) {
	a0, _, a1, _ := frame_uvs({10, 20, 30, 40}, 100, 200, false)
	b0, v0, b1, v1 := frame_uvs({10, 20, 30, 40}, 100, 200, true)
	testing.expect_value(t, b0, a1)
	testing.expect_value(t, b1, a0)
	testing.expect_value(t, v0, f32(0.1))
	testing.expect_value(t, v1, f32(0.3))
}

@(test)
sprite_feet_quad_no_flip :: proc(t: ^testing.T) {
	// feet (400,500), source 100x200, pivot feet, trim (10,20), packed 80x160
	x0, y0, x1, y1 := sprite_feet_quad(
		{400, 500},
		100,
		200,
		{10, 20},
		{80, 160},
		{0.5, 1.0},
		false,
	)
	testing.expect_value(t, x0, f32(360)) // 400 - 50 + 10
	testing.expect_value(t, y0, f32(320)) // 500 - 200 + 20
	testing.expect_value(t, x1, f32(440))
	testing.expect_value(t, y1, f32(480))
}

@(test)
sprite_feet_quad_flip_x :: proc(t: ^testing.T) {
	x0, y0, x1, y1 := sprite_feet_quad(
		{400, 500},
		100,
		200,
		{5, 20},
		{80, 160},
		{0.5, 1.0},
		true,
	)
	// canvas_left = 350; trim_x_draw = 100 - 5 - 80 = 15 → x0 = 365
	testing.expect_value(t, x0, f32(365))
	testing.expect_value(t, y0, f32(320))
	testing.expect_value(t, x1, f32(445))
	testing.expect_value(t, y1, f32(480))
}
