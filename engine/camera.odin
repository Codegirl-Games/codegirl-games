package engine

Camera :: struct {
	position: Vec2,
	anchor:   Vec2,
}

camera_default :: proc() -> Camera {
	return Camera{position = {0, 0}, anchor = {0.5, 0.5}}
}

world_to_screen :: proc(cam: Camera, world: Vec2, viewport: Vec2) -> Vec2 {
	return {
		world.x - cam.position.x + viewport.x * cam.anchor[0],
		world.y - cam.position.y + viewport.y * cam.anchor[1],
	}
}
