package engine

import "core:testing"

@(test)
camera_default_values :: proc(t: ^testing.T) {
	cam := camera_default()
	testing.expect_value(t, cam.position, Vec2{0, 0})
	testing.expect_value(t, cam.anchor, Vec2{0.5, 0.5})
}

@(test)
world_to_screen_centered_identity :: proc(t: ^testing.T) {
	cam := Camera {
		position = {400, 500},
		anchor   = {0.5, 0.5},
	}
	viewport := Vec2{800, 600}
	screen := world_to_screen(cam, cam.position, viewport)
	testing.expect_value(t, screen.x, f32(400))
	testing.expect_value(t, screen.y, f32(300))
}

@(test)
world_to_screen_origin_cam :: proc(t: ^testing.T) {
	cam := Camera {
		position = {0, 0},
		anchor   = {0.5, 0.5},
	}
	screen := world_to_screen(cam, {10, 20}, {200, 100})
	testing.expect_value(t, screen.x, f32(110))
	testing.expect_value(t, screen.y, f32(70))
}

@(test)
world_to_screen_top_left_anchor :: proc(t: ^testing.T) {
	cam := Camera {
		position = {5, 7},
		anchor   = {0, 0},
	}
	screen := world_to_screen(cam, {15, 27}, {800, 600})
	testing.expect_value(t, screen.x, f32(10))
	testing.expect_value(t, screen.y, f32(20))
}
