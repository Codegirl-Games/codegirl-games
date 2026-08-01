package engine

import sdl "vendor:sdl3"

Vec2 :: [2]f32

Sprite :: struct {
	data:     ^Character_Data,
	position: Vec2,
	clip:     string,
	frame:    int,
	time:     f32,
	flip_x:   bool,
}

spawn_sprite :: proc(
	data: ^Character_Data,
	position: Vec2,
	clip: string = "idle",
	frame: int = 0,
) -> Sprite {
	sprite := Sprite {
		data     = data,
		position = position,
	}
	set_sprite_clip(&sprite, clip)
	if frame != 0 {
		c, ok := character_clip(sprite.data, sprite.clip)
		if ok {
			if frame < 0 {
				sprite.frame = 0
			} else if frame >= len(c.frames) {
				sprite.frame = len(c.frames) - 1
			} else {
				sprite.frame = frame
			}
		}
	}
	return sprite
}

update_sprite :: proc(sprite: ^Sprite, dt: f32) {
	if sprite == nil || sprite.data == nil do return
	if dt <= 0 do return

	clip, ok := character_clip(sprite.data, sprite.clip)
	if !ok do return

	frame_count := len(clip.frames)
	if frame_count <= 0 do return

	if sprite.frame < 0 do sprite.frame = 0
	if sprite.frame >= frame_count do sprite.frame = frame_count - 1

	if clip.fps <= 0 do return

	sprite.time += dt
	frame_duration := 1.0 / clip.fps

	for sprite.time >= frame_duration {
		sprite.time -= frame_duration
		next := sprite.frame + 1

		if next >= frame_count {
			if clip.loop {
				sprite.frame = 0
			} else {
				sprite.frame = frame_count - 1
				sprite.time = 0
				break
			}
		} else {
			sprite.frame = next
		}
	}
}

to_clip :: proc(px, py, sw, sh: f32) -> [2]f32 {
	return {
		px / sw * 2 - 1,
		1 - py / sh * 2, // flip y (window pixels are y-down)
	}
}

draw_sprite :: proc(app: ^App, sprite: ^Sprite) {
	if app.cmd == nil || app.swapchain_texture == nil {
		return
	}
	if sprite == nil || sprite.data == nil || sprite.data.texture == nil {
		return
	}
	if len(app.draw_list) >= MAX_SPRITES {
		return
	}

	frame, ok := character_frame(sprite.data, sprite.clip, sprite.frame)
	if !ok {
		return
	}

	src_w := f32(frame.source_size[0])
	src_h := f32(frame.source_size[1])
	if src_w <= 0 do src_w = f32(frame.rect[2])
	if src_h <= 0 do src_h = f32(frame.rect[3])

	fw := f32(frame.rect[2])
	fh := f32(frame.rect[3])
	trim_x := f32(frame.trim_offset[0])
	trim_y := f32(frame.trim_offset[1])
	pivot := sprite.data.def.pivot

	canvas_top := sprite.position.y - src_h * pivot[1]
	x0_px, y0_px: f32
	if sprite.flip_x {
		canvas_left := sprite.position.x - (1.0 - pivot[0]) * src_w
		x0_px = canvas_left + (src_w - trim_x - fw)
		y0_px = canvas_top + trim_y
	} else {
		canvas_left := sprite.position.x - src_w * pivot[0]
		x0_px = canvas_left + trim_x
		y0_px = canvas_top + trim_y
	}
	x1_px := x0_px + fw
	y1_px := y0_px + fh

	sw := f32(app.swapchain_w)
	sh := f32(app.swapchain_h)
	p0 := to_clip(x0_px, y0_px, sw, sh)
	p1 := to_clip(x1_px, y0_px, sw, sh)
	p2 := to_clip(x1_px, y1_px, sw, sh)
	p3 := to_clip(x0_px, y1_px, sw, sh)

	tex_w := f32(sprite.data.width)
	tex_h := f32(sprite.data.height)
	u0 := f32(frame.rect[0]) / tex_w
	v0 := f32(frame.rect[1]) / tex_h
	u1 := f32(frame.rect[0] + frame.rect[2]) / tex_w
	v1 := f32(frame.rect[1] + frame.rect[3]) / tex_h
	if sprite.flip_x do u0, u1 = u1, u0

	verts := [SPRITE_VERT_COUNT]Vertex {
		{pos = p0, uv = {u0, v0}},
		{pos = p1, uv = {u1, v0}},
		{pos = p2, uv = {u1, v1}},
		{pos = p0, uv = {u0, v0}},
		{pos = p2, uv = {u1, v1}},
		{pos = p3, uv = {u0, v1}},
	}

	append(
		&app.draw_list,
		Queued_Sprite{texture = sprite.data.texture, verts = verts},
	)
}

set_sprite_clip :: proc(sprite: ^Sprite, clip: string) {
	if sprite == nil || sprite.data == nil do return

	if sprite.clip == clip do return

	_, ok := character_clip(sprite.data, clip)
	if !ok do return

	sprite.clip = clip
	sprite.frame = 0
	sprite.time = 0
}

sprite_quad_origin :: proc(position: Vec2, size: Vec2, pivot: [2]f32) -> Vec2 {
	return {position.x - size.x * pivot[0], position.y - size.y * pivot[1]}
}

set_sprite_flip_x :: proc(sprite: ^Sprite, flip: bool) {
	if sprite == nil do return
	sprite.flip_x = flip
}
