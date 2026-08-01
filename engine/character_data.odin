package engine

import "core:encoding/json"
import "core:fmt"
import "core:mem"
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
	texture: ^sdl.GPUTexture,
	width:   int,
	height:  int,
}

parse_char_def :: proc(file_data: []u8) -> (Char_Def, bool) {
	def: Char_Def
	if err := json.unmarshal(file_data, &def); err != nil {
		fmt.eprintfln("json unmarshal failed: %v", err)
		return {}, false
	}
	return def, true
}

load_character_data :: proc(app: ^App, character_json_path: string) -> (Character_Data, bool) {
	file_data, read_err := os.read_entire_file(character_json_path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("failed to read %s: %v", character_json_path, read_err)
		return {}, false
	}

	defer delete(file_data)

	out: Character_Data
	ok: bool
	out.def, ok = parse_char_def(file_data)
	if !ok {
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

	rgba_surface := surface
	converted_surface: ^sdl.Surface
	defer {
		if converted_surface != nil do sdl.DestroySurface(converted_surface)
	}
	if surface.format != .ABGR8888 {
		converted_surface = sdl.ConvertSurface(surface, .ABGR8888)
		if converted_surface == nil {
			fmt.eprintfln("ConvertSurface(ABGR8888) failed: %s", sdl.GetError())
			return {}, false
		}
		rgba_surface = converted_surface
	}

	out.width = int(rgba_surface.w)
	out.height = int(rgba_surface.h)

	out.texture = sdl.CreateGPUTexture(
		app.device,
		{
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = u32(out.width),
			height = u32(out.height),
			layer_count_or_depth = 1,
			num_levels = 1,
			sample_count = ._1,
		},
	)

	if out.texture == nil {
		fmt.eprintfln("CreateGPUTexture failed: %s", sdl.GetError())
		return {}, false
	}

	upload_size := int(rgba_surface.pitch) * int(rgba_surface.h)
	tbuf := sdl.CreateGPUTransferBuffer(app.device, {usage = .UPLOAD, size = u32(upload_size)})

	if tbuf == nil {
		fmt.eprintfln("CreateGPUTransferBuffer failed: %s", sdl.GetError())
		sdl.ReleaseGPUTexture(app.device, out.texture)
		return {}, false
	}

	map_ptr := sdl.MapGPUTransferBuffer(app.device, tbuf, false)

	if map_ptr == nil {
		fmt.eprintfln("MapGPUTransferBuffer failed: %s", sdl.GetError())
		sdl.ReleaseGPUTransferBuffer(app.device, tbuf)
		sdl.ReleaseGPUTexture(app.device, out.texture)
		return {}, false
	}

	mem.copy(map_ptr, rgba_surface.pixels, upload_size)
	sdl.UnmapGPUTransferBuffer(app.device, tbuf)

	cmd := sdl.AcquireGPUCommandBuffer(app.device)
	if cmd == nil {
		fmt.eprintfln("AcquireGPUCommandBuffer failed: %s", sdl.GetError())
		sdl.ReleaseGPUTransferBuffer(app.device, tbuf)
		sdl.ReleaseGPUTexture(app.device, out.texture)
		return {}, false
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)

	transfer := sdl.GPUTextureTransferInfo {
		transfer_buffer = tbuf,
		offset          = 0,
		pixels_per_row  = u32(rgba_surface.pitch / 4), // RGBA8888 => 4 bytes/pixel
		rows_per_layer  = u32(rgba_surface.h),
	}
	region := sdl.GPUTextureRegion {
		texture   = out.texture,
		mip_level = 0,
		layer     = 0,
		x         = 0,
		y         = 0,
		z         = 0,
		w         = u32(rgba_surface.w),
		h         = u32(rgba_surface.h),
		d         = 1,
	}
	sdl.UploadToGPUTexture(copy_pass, transfer, region, false)
	sdl.EndGPUCopyPass(copy_pass)
	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	if fence == nil {
		fmt.eprintfln(
			"SubmitGPUCommandBufferAndAcquireFence (texture upload) failed: %s",
			sdl.GetError(),
		)
		sdl.ReleaseGPUTransferBuffer(app.device, tbuf)
		sdl.ReleaseGPUTexture(app.device, out.texture)
		return {}, false
	}
	defer sdl.ReleaseGPUFence(app.device, fence)

	if !sdl.WaitForGPUFences(app.device, true, &fence, 1) {
		fmt.eprintfln("WaitForGPUFences (texture upload) failed: %s", sdl.GetError())
		sdl.ReleaseGPUTransferBuffer(app.device, tbuf)
		sdl.ReleaseGPUTexture(app.device, out.texture)
		return {}, false
	}

	sdl.ReleaseGPUTransferBuffer(app.device, tbuf)

	return out, true
}

destroy_character_data :: proc(app: ^App, data: ^Character_Data) {
	if data.texture != nil {
		// Ensure no in-flight draw command is still sampling this texture.
		if app != nil && app.device != nil {
			_ = sdl.WaitForGPUIdle(app.device)
		}
		sdl.ReleaseGPUTexture(app.device, data.texture)
	}
	data^ = {}
}

character_clip :: proc(data: ^Character_Data, clip_name: string) -> (clip: Clip_Def, ok: bool) {
	if data == nil do return {}, false
	character, found := data.def.clips[clip_name]
	if !found || len(character.frames) == 0 do return {}, false
	return character, true
}

character_frame :: proc(
	data: ^Character_Data,
	clip_name: string,
	frame_index: int,
) -> (
	frame: Frame_Def,
	ok: bool,
) {
	if data == nil do return {}, false
	clip, found := data.def.clips[clip_name]
	if !found || frame_index < 0 || frame_index >= len(clip.frames) {
		return {}, false
	}
	return clip.frames[frame_index], true
}

character_frame_rect :: proc(
	data: ^Character_Data,
	clip_name: string,
	frame_index: int,
) -> (
	rect: [4]int,
	ok: bool,
) {
	frame, found := character_frame(data, clip_name, frame_index)
	if !found do return {}, false
	return frame.rect, true
}
