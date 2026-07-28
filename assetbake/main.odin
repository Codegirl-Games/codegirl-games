package main

import "core:bytes"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import stbi "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"

// Authoring-side clip block from manifest.json
Clip_Manifest :: struct {
	folder: string,
	fps:    f32,
	loop:   bool,
}

// Authoring-side character manifest
Manifest :: struct {
	id:              string,
	pixels_per_unit: f32,
	pivot:           [2]f32,
	clips:           map[string]Clip_Manifest,
}

// Runtime frame description written to *.char.json
Frame_Def :: struct {
	rect:        [4]int, // x, y, w, h in atlas pixels
	source_size: [2]int,
	trim_offset: [2]int,
}

// Runtime clip description
Clip_Def :: struct {
	loop:   bool,
	fps:    f32,
	frames: []Frame_Def,
}

// Runtime character package metadata
Char_Def :: struct {
	version:         int,
	id:              string,
	atlas:           string, // filename relative to this .char.json
	pixels_per_unit: f32,
	pivot:           [2]f32,
	clips:           map[string]Clip_Def,
}

// Packed atlas pixels + per-frame rects (indexed like the combined frames list)
Atlas :: struct {
	pixels: []u8,
	width:  int,
	height: int,
	rects:  [][4]int, // [x, y, w, h] per frame; sizes may differ across clips
}

// Where one clip's frames sit inside the packed atlas frame list
Clip_Range :: struct {
	name:  string,
	clip:  Clip_Manifest,
	start: int, // index into the combined frames / atlas rects
	count: int,
}

main :: proc() {
	if len(os.args) < 3 {
		fmt.eprintfln("usage: assetbake <character dir> <output dir>")
		os.exit(1)
	}
	bake_character(os.args[1], os.args[2])
}

// bake_character is the full pipeline for one character folder.
bake_character :: proc(in_dir, out_dir: string) {
	manifest := load_manifest(in_dir)
	if len(manifest.clips) == 0 {
		fmt.eprintfln("manifest has no clips")
		os.exit(1)
	}

	// Load every clip from the manifest into one frame list (deterministic clip order)
	frames, ranges := load_all_clips(in_dir, manifest)
	defer destroy_frames(frames)
	defer delete(ranges)

	// Clips may differ in size (idle vs walk); pack with a real rectangle packer
	atlas := pack_atlas(frames)
	defer delete(atlas.pixels)
	defer delete(atlas.rects)

	ensure_dir(out_dir)

	atlas_name := fmt.tprintf("%s.atlas.png", manifest.id)
	write_atlas_png(out_dir, atlas_name, atlas)

	char_def := build_char_def(manifest, ranges, atlas_name, atlas)
	defer destroy_char_def(char_def)

	write_char_json(out_dir, fmt.tprintf("%s.char.json", manifest.id), char_def)
	fmt.printfln("baked %s (%d clips, %d frames)", manifest.id, len(ranges), len(frames))
}

// load_manifest reads content/.../manifest.json into a Manifest.
load_manifest :: proc(character_dir: string) -> Manifest {
	path, join_err := filepath.join({character_dir, "manifest.json"})
	if join_err != nil {
		fmt.eprintfln("join failed: %v", join_err)
		os.exit(1)
	}
	defer delete(path)

	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("failed to read %s: %v", path, read_err)
		os.exit(1)
	}
	defer delete(data)

	manifest: Manifest
	if err := json.unmarshal(data, &manifest); err != nil {
		fmt.eprintfln("json unmarshal failed: %v", err)
		os.exit(1)
	}
	return manifest
}

// load_all_clips walks every manifest clip (names sorted), loads PNGs, and records atlas ranges.
// Within a clip, all frames must share one size. Different clips may use different sizes.
// Caller owns frames (destroy_frames) and ranges (delete).
load_all_clips :: proc(character_dir: string, manifest: Manifest) -> ([]^image.Image, []Clip_Range) {
	clip_names := sorted_clip_names(manifest)
	defer delete(clip_names)

	loaded: [dynamic]^image.Image
	ranges := make([]Clip_Range, len(clip_names))

	for name, i in clip_names {
		clip := manifest.clips[name]
		paths := list_sorted_frame_paths(character_dir, clip.folder)
		defer delete_paths(paths)

		start := len(loaded)
		for path in paths {
			append(&loaded, load_frame(path))
		}

		// Enforce uniform size inside this clip only
		validate_clip_frame_sizes(name, loaded[start:])

		ranges[i] = Clip_Range {
			name  = name,
			clip  = clip,
			start = start,
			count = len(paths),
		}
		fw := loaded[start].width
		fh := loaded[start].height
		fmt.printfln(
			"clip %s: %d frames %dx%d (atlas slots %d..%d)",
			name,
			len(paths),
			fw,
			fh,
			start,
			start + len(paths) - 1,
		)
	}

	if len(loaded) == 0 {
		fmt.eprintfln("no frames loaded")
		os.exit(1)
	}

	frames := make([]^image.Image, len(loaded))
	copy(frames, loaded[:])
	delete(loaded)

	fmt.printfln("loaded %d frames total across %d clips", len(frames), len(ranges))
	return frames, ranges
}

// validate_clip_frame_sizes requires every frame in one clip to match the first frame's size.
validate_clip_frame_sizes :: proc(clip_name: string, frames: []^image.Image) {
	if len(frames) == 0 {
		return
	}
	fw := frames[0].width
	fh := frames[0].height
	for frame, i in frames[1:] {
		if frame.width != fw || frame.height != fh {
			fmt.eprintfln(
				"clip %s: frame size mismatch at %d: got %dx%d, expected %dx%d",
				clip_name,
				i + 1,
				frame.width,
				frame.height,
				fw,
				fh,
			)
			os.exit(1)
		}
	}
}

// sorted_clip_names returns manifest clip keys in alphabetical order for stable bakes.
sorted_clip_names :: proc(manifest: Manifest) -> []string {
	names := make([]string, len(manifest.clips))
	i := 0
	for name in manifest.clips {
		names[i] = name // keys owned by the map; do not delete individually
		i += 1
	}
	slice.sort(names)
	return names
}

// list_sorted_frame_paths globs *.png under folder and sorts by trailing frame number.
// Caller owns the returned paths (use delete_paths).
list_sorted_frame_paths :: proc(character_dir, folder: string) -> []string {
	clip_dir, clip_join_err := filepath.join({character_dir, folder})
	if clip_join_err != nil {
		fmt.eprintfln("join failed: %v", clip_join_err)
		os.exit(1)
	}
	defer delete(clip_dir)

	pattern, pattern_err := filepath.join({clip_dir, "*.png"})
	if pattern_err != nil {
		fmt.eprintfln("pattern join failed: %v", pattern_err)
		os.exit(1)
	}
	defer delete(pattern)

	matches, glob_err := filepath.glob(pattern)
	if glob_err != nil {
		fmt.eprintfln("glob failed: %v", glob_err)
		os.exit(1)
	}
	if len(matches) == 0 {
		fmt.eprintfln("no pngs in %s", clip_dir)
		os.exit(1)
	}

	// Sort by trailing frame number so _10 comes after _9, not after _1
	slice.sort_by(matches, proc(a, b: string) -> bool {
		return frame_index(a) < frame_index(b)
	})
	return matches
}

delete_paths :: proc(paths: []string) {
	for p in paths {
		delete(p)
	}
	delete(paths)
}

load_frame :: proc(path: string) -> ^image.Image {
	img, err := png.load_from_file(path)
	if err != nil {
		fmt.eprintfln("image load failed (%s): %v", path, err)
		os.exit(1)
	}
	if img.channels != 4 {
		fmt.eprintfln("expected RGBA for %s, got %d channels", path, img.channels)
		os.exit(1)
	}
	return img
}

destroy_frames :: proc(frames: []^image.Image) {
	for f in frames {
		image.destroy(f)
	}
	delete(frames)
}

// pack_atlas packs variable-size frames with stb_rect_pack and blits them into one sheet.
// Caller owns atlas.pixels and atlas.rects.
pack_atlas :: proc(frames: []^image.Image) -> Atlas {
	PADDING :: 1 // 1px gap to reduce bleeding if filtered later

	pack_rects := make([]stbrp.Rect, len(frames))
	defer delete(pack_rects)

	total_area := 0
	max_w := 0
	max_h := 0
	for frame, i in frames {
		w := frame.width + PADDING
		h := frame.height + PADDING
		pack_rects[i] = stbrp.Rect {
			id = c.int(i), // pack_rects may reorder; id maps back to frame index
			w  = stbrp.Coord(w),
			h  = stbrp.Coord(h),
		}
		total_area += w * h
		max_w = max(max_w, w)
		max_h = max(max_h, h)
	}

	// Grow a square-ish atlas until everything fits
	side := max(max_w, max_h, int(math.ceil(math.sqrt(f64(total_area)))))
	atlas_w, atlas_h := 0, 0
	packed := false
	for attempt in 0 ..< 16 {
		atlas_w = side
		atlas_h = side
		if try_pack_rects(atlas_w, atlas_h, pack_rects) {
			packed = true
			break
		}
		side = max(side + 64, int(math.ceil(f64(side) * 1.25)))
		_ = attempt
	}
	if !packed {
		fmt.eprintfln("failed to pack %d frames into an atlas", len(frames))
		os.exit(1)
	}

	pixels := make([]u8, atlas_w * atlas_h * 4) // transparent
	rects := make([][4]int, len(frames))

	// Blit using each rect's id (array order may have changed during packing)
	for pr in pack_rects {
		if !pr.was_packed {
			fmt.eprintfln("frame %d was not packed", pr.id)
			os.exit(1)
		}
		idx := int(pr.id)
		frame := frames[idx]
		fw := frame.width
		fh := frame.height
		dst_x := int(pr.x)
		dst_y := int(pr.y)

		src := bytes.buffer_to_bytes(&frame.pixels)
		for y in 0 ..< fh {
			src_row := src[y * fw * 4:(y + 1) * fw * 4]
			dst_i := ((dst_y + y) * atlas_w + dst_x) * 4
			copy(pixels[dst_i:], src_row)
		}

		rects[idx] = {dst_x, dst_y, fw, fh}
	}

	fmt.printfln("packed atlas %dx%d", atlas_w, atlas_h)
	return Atlas {
		pixels = pixels,
		width  = atlas_w,
		height = atlas_h,
		rects  = rects,
	}
}

// try_pack_rects attempts to place all rects into a width×height bin.
try_pack_rects :: proc(width, height: int, rects: []stbrp.Rect) -> bool {
	nodes := make([]stbrp.Node, width)
	defer delete(nodes)

	ctx: stbrp.Context
	stbrp.init_target(&ctx, c.int(width), c.int(height), raw_data(nodes), c.int(len(nodes)))
	stbrp.setup_allow_out_of_mem(&ctx, true)

	return stbrp.pack_rects(&ctx, raw_data(rects), c.int(len(rects))) != 0
}

ensure_dir :: proc(path: string) {
	if err := os.make_directory_all(path); err != nil && err != .Exist {
		fmt.eprintfln("failed to create output dir %s: %v", path, err)
		os.exit(1)
	}
}

// write_atlas_png writes atlas pixels to out_dir/atlas_name via stb_image_write.
write_atlas_png :: proc(out_dir, atlas_name: string, atlas: Atlas) {
	atlas_path, atlas_join_err := filepath.join({out_dir, atlas_name})
	if atlas_join_err != nil {
		fmt.eprintfln("atlas path join failed: %v", atlas_join_err)
		os.exit(1)
	}
	defer delete(atlas_path)

	atlas_cpath := strings.clone_to_cstring(atlas_path)
	defer delete(atlas_cpath)

	if stbi.write_png(
		atlas_cpath,
		i32(atlas.width),
		i32(atlas.height),
		4,
		raw_data(atlas.pixels),
		i32(atlas.width * 4),
	) == 0 {
		fmt.eprintfln("failed to write atlas: %s", atlas_path)
		os.exit(1)
	}
	fmt.printfln("wrote %s (%dx%d)", atlas_path, atlas.width, atlas.height)
}

// build_char_def builds runtime metadata for every baked clip using packed rects.
build_char_def :: proc(
	manifest: Manifest,
	ranges: []Clip_Range,
	atlas_name: string,
	atlas: Atlas,
) -> Char_Def {
	char_clips := make(map[string]Clip_Def)

	for range in ranges {
		frame_defs := make([]Frame_Def, range.count)
		for i in 0 ..< range.count {
			slot := range.start + i
			r := atlas.rects[slot]
			frame_defs[i] = Frame_Def {
				rect        = r,
				source_size = {r[2], r[3]},
				trim_offset = {0, 0}, // no trimming in v1
			}
		}

		char_clips[range.name] = Clip_Def {
			loop   = range.clip.loop,
			fps    = range.clip.fps,
			frames = frame_defs,
		}
	}

	return Char_Def {
		version         = 1,
		id              = manifest.id,
		atlas           = atlas_name,
		pixels_per_unit = manifest.pixels_per_unit,
		pivot           = manifest.pivot,
		clips           = char_clips,
	}
}

destroy_char_def :: proc(char_def: Char_Def) {
	for _, clip in char_def.clips {
		delete(clip.frames)
	}
	delete(char_def.clips)
}

write_char_json :: proc(out_dir, char_name: string, char_def: Char_Def) {
	char_json, marshal_err := json.marshal(char_def, {pretty = true, use_spaces = true})
	if marshal_err != nil {
		fmt.eprintfln("json marshal failed: %v", marshal_err)
		os.exit(1)
	}
	defer delete(char_json)

	char_path, char_join_err := filepath.join({out_dir, char_name})
	if char_join_err != nil {
		fmt.eprintfln("char path join failed: %v", char_join_err)
		os.exit(1)
	}
	defer delete(char_path)

	if err := os.write_entire_file(char_path, char_json); err != nil {
		fmt.eprintfln("failed to write %s: %v", char_path, err)
		os.exit(1)
	}
	fmt.printfln("wrote %s", char_path)
}

// frame_index pulls the trailing number from names like skeleton-Idle_17.png
frame_index :: proc(path: string) -> int {
	name := filepath.stem(path)
	idx := strings.last_index_byte(name, '_')
	if idx < 0 {
		return 0
	}
	n, _ := strconv.parse_int(name[idx + 1:])
	return n
}
