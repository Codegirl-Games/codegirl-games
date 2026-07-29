package engine

import sdl "vendor:sdl3"

Vec2 :: [2]f32

Sprite :: struct {
	data:     ^Character_Data,
	position: Vec2,
	clip:     string,
	frame:    int,
}

spawn_sprite :: proc(
	data: ^Character_Data,
	position: Vec2,
	clip: string = "idle",
	frame: int = 0,
) -> Sprite {
	return Sprite{data = data, position = position, clip = clip, frame = frame}
}

// stubbed for later
update_sprite :: proc(sprite: ^Sprite, dt: f32) {
	_ = sprite
	_ = dt
}

draw_sprite :: proc(renderer: ^sdl.Renderer, sprite: ^Sprite) {
	assert(sprite.data != nil)
	rect, ok := character_frame_rect(sprite.data, sprite.clip, sprite.frame)
	if !ok {
		return
	}

	w := f32(rect[2])
	h := f32(rect[3])
	dst := sdl.FRect {
		x = sprite.position.x - w * 0.5,
		y = sprite.position.y - h,
		w = w,
		h = h,
	}
	src := sdl.FRect {
		x = f32(rect[0]),
		y = f32(rect[1]),
		w = w,
		h = h,
	}
	sdl.RenderTexture(renderer, sprite.data.texture, &src, &dst)
}
