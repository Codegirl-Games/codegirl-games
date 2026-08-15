package engine

import sdl "vendor:sdl3"

Vec2 :: [2]f32

Sprite :: struct {
	data:      ^Character_Data,
	position:  Vec2,
	clip:      string,
	clip_def:  Clip_Def,
	has_clip:  bool,
	frame:     int,
	time:      f32,
	flip_x:    bool,
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
	if frame != 0 && sprite.has_clip {
		c := sprite.clip_def
		if frame < 0 {
			sprite.frame = 0
		} else if frame >= len(c.frames) {
			sprite.frame = len(c.frames) - 1
		} else {
			sprite.frame = frame
		}
	}
	return sprite
}

update_sprite :: proc(sprite: ^Sprite, dt: f32) {
	if sprite == nil || sprite.data == nil do return
	if dt <= 0 do return
	if !sprite.has_clip do return

	clip := sprite.clip_def

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

// Axis-aligned quad: two unique x and y values, so scale once and reuse.
sprite_quad_to_clip :: proc(x0, y0, x1, y1, sw, sh: f32) -> [4]Vec2 {
	sx := 2.0 / sw
	sy := 2.0 / sh

	left := x0 * sx - 1
	right := x1 * sx - 1
	top := 1 - y0 * sy
	bottom := 1 - y1 * sy

	return {
		{left, top},
		{right, top},
		{right, bottom},
		{left, bottom},
	}
}

draw_sprite :: proc(app: ^App, sprite: ^Sprite) {
	draw_sprite_batched(app, sprite, 0)
}

// Nonzero batch_group lets end_frame regroup consecutive same-group sprites by
// texture. Group 0 keeps exact submission order for correct alpha overlap.
draw_sprite_batched :: proc(app: ^App, sprite: ^Sprite, batch_group: u32) {
	if app.cmd == nil || app.swapchain_texture == nil {
		return
	}
	if sprite == nil || sprite.data == nil || sprite.data.texture == nil {
		return
	}
	if len(app.draw_list) >= MAX_SPRITES {
		return
	}
	if !sprite.has_clip do return
	if sprite.frame < 0 || sprite.frame >= len(sprite.clip_def.frames) {
		return
	}

	frame := sprite.clip_def.frames[sprite.frame]

	src_w := f32(frame.source_size[0])
	src_h := f32(frame.source_size[1])
	if src_w <= 0 do src_w = f32(frame.rect[2])
	if src_h <= 0 do src_h = f32(frame.rect[3])

	fw := f32(frame.rect[2])
	fh := f32(frame.rect[3])
	trim_x := f32(frame.trim_offset[0])
	trim_y := f32(frame.trim_offset[1])
	pivot := sprite.data.def.pivot

	viewport := Vec2{f32(app.swapchain_w), f32(app.swapchain_h)}
	feet := world_to_screen(app.camera, sprite.position, viewport)

	x0_px, y0_px, x1_px, y1_px := sprite_feet_quad(
		feet,
		src_w,
		src_h,
		{trim_x, trim_y},
		{fw, fh},
		pivot,
		sprite.flip_x,
	)

	sw := f32(app.swapchain_w)
	sh := f32(app.swapchain_h)
	points := sprite_quad_to_clip(x0_px, y0_px, x1_px, y1_px, sw, sh)
	p0, p1, p2, p3 := points[0], points[1], points[2], points[3]

	tex_w := f32(sprite.data.width)
	tex_h := f32(sprite.data.height)
	u0, v0, u1, v1 := frame_uvs(frame.rect, tex_w, tex_h, sprite.flip_x)

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
		Queued_Sprite {
			texture = sprite.data.texture,
			verts = verts,
			batch_group = batch_group,
		},
	)
}

set_sprite_clip :: proc(sprite: ^Sprite, clip: string) {
	if sprite == nil || sprite.data == nil do return

	if sprite.clip == clip && sprite.has_clip do return

	def, ok := character_clip(sprite.data, clip)
	if !ok do return

	set_sprite_clip_def(sprite, clip, def)
}

// Applies a pre-resolved clip without looking up the character clip map.
// Use when callers already hold Clip_Def (e.g. thrashing between known clips).
set_sprite_clip_def :: proc(sprite: ^Sprite, clip: string, def: Clip_Def) {
	if sprite == nil do return
	if len(def.frames) == 0 do return

	if sprite.clip == clip && sprite.has_clip do return

	sprite.clip = clip
	sprite.clip_def = def
	sprite.has_clip = true
	sprite.frame = 0
	sprite.time = 0
}

sprite_quad_origin :: proc(position: Vec2, size: Vec2, pivot: [2]f32) -> Vec2 {
	return {position.x - size.x * pivot[0], position.y - size.y * pivot[1]}
}

frame_uvs :: proc(rect: [4]int, tex_w, tex_h: f32, flip_x: bool) -> (u0, v0, u1, v1: f32) {
	u0 = f32(rect[0]) / tex_w
	v0 = f32(rect[1]) / tex_h
	u1 = f32(rect[0] + rect[2]) / tex_w
	v1 = f32(rect[1] + rect[3]) / tex_h
	if flip_x do u0, u1 = u1, u0
	return
}

sprite_feet_quad :: proc(
	feet: Vec2,
	src_w, src_h: f32,
	trim: Vec2,
	size: Vec2,
	pivot: [2]f32,
	flip_x: bool,
) -> (
	x0, y0, x1, y1: f32,
) {
	canvas_top := feet.y - src_h * pivot[1]
	if flip_x {
		canvas_left := feet.x - (1.0 - pivot[0]) * src_w
		x0 = canvas_left + (src_w - trim.x - size.x)
		y0 = canvas_top + trim.y
	} else {
		canvas_left := feet.x - src_w * pivot[0]
		x0 = canvas_left + trim.x
		y0 = canvas_top + trim.y
	}
	x1 = x0 + size.x
	y1 = y0 + size.y
	return
}

set_sprite_flip_x :: proc(sprite: ^Sprite, flip: bool) {
	if sprite == nil do return
	sprite.flip_x = flip
}
