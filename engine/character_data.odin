package engine

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

Frame_Def :: struct {
	rect:        [4]int,
	source_size: [2]int,
	trim_offset: [2]int,
}

Clip_Def :: struct {
	loop:   bool,
	fps:    f32,
	frames: []Frame_Def,
}

Char_Def :: struct {
	version:         int,
	id:              string,
	atlas:           string,
	pixels_per_unit: f32,
	pivot:           [2]f32,
	clips:           map[string]Clip_Def,
}

Character_Data :: struct {
	def:     Char_Def,
	texture: ^sdl.Texture,
}

load_character_data :: proc(
	renderer: ^sdl.Renderer,
	character_json_path: string,
) -> (
	Character_Data,
	bool,
) {
	file_data, read_err := os.read_entire_file(character_json_path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("failed to read %s: %v", character_json_path, read_err)
		return {}, false
	}

	defer delete(file_data)

	out: Character_Data
	if err := json.unmarshal(file_data, &out.def); err != nil {
		fmt.eprintfln("json unmarshal failed: %v", err)
		return {}, false
	}

	// filepath.dir returns a substring of the path — do NOT delete it
	dir := filepath.dir(character_json_path)

	atlas_path, join_err := filepath.join({dir, out.def.atlas})
	if join_err != nil {
		fmt.eprintfln("atlas join failed: %v", join_err)
		return {}, false
	}

	defer delete(atlas_path)

	c_path := strings.clone_to_cstring(atlas_path)
	defer delete(c_path)

	surface := sdl.LoadPNG(c_path)
	if surface == nil {
		fmt.eprintfln("LoadPNG failed: %s", sdl.GetError())
		return {}, false
	}
	defer sdl.DestroySurface(surface)

	out.texture = sdl.CreateTextureFromSurface(renderer, surface)
	if out.texture == nil {
		fmt.eprintfln("CreateTextureFromSurface failed: %s", sdl.GetError())
		return {}, false
	}
	sdl.SetTextureScaleMode(out.texture, .NEAREST)
	return out, true
}

destroy_character_data :: proc(data: ^Character_Data) {
	if data.texture != nil {
		sdl.DestroyTexture(data.texture)
	}
	data^ = {}
}

character_frame_rect :: proc(
	data: ^Character_Data,
	clip_name: string,
	frame_index: int,
) -> (
	rect: [4]int,
	ok: bool,
) {
	clip, found := data.def.clips[clip_name]
	if !found || frame_index < 0 || frame_index >= len(clip.frames) {
		return {}, false
	}

	return clip.frames[frame_index].rect, true
}
