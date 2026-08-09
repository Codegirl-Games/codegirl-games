package engine

import "core:fmt"
import "core:mem"
import "core:path/filepath"
import sdl "vendor:sdl3"

Vertex :: struct {
	pos: [2]f32, // clip space, -1..1
	uv:  [2]f32, // 0..1 atlas coords (used later in draw_sprite)
}

SPRITE_VERT_COUNT :: 6
MAX_SPRITES :: 128
SPRITE_VERTS_SIZE :: SPRITE_VERT_COUNT * size_of(Vertex)
VERTEX_BUFFER_SIZE :: MAX_SPRITES * SPRITE_VERTS_SIZE

Queued_Sprite :: struct {
	texture: ^sdl.GPUTexture,
	verts:   [SPRITE_VERT_COUNT]Vertex,
}

App :: struct {
	window:            ^sdl.Window,
	device:            ^sdl.GPUDevice,
	shader:            Shader_Runtime,
	pipeline:          ^sdl.GPUGraphicsPipeline,
	sampler:           ^sdl.GPUSampler,
	cmd:               ^sdl.GPUCommandBuffer,
	render_pass:       ^sdl.GPURenderPass,
	swapchain_texture: ^sdl.GPUTexture,
	swapchain_w:       u32,
	swapchain_h:       u32,
	vertex_buffer:     ^sdl.GPUBuffer,
	transfer_buffer:   ^sdl.GPUTransferBuffer,
	draw_list:         [dynamic]Queued_Sprite,
	clear_color:       sdl.FColor,
	camera:            Camera,
}

Shader_Backend :: enum {
	Vulkan_SPIRV,
	DSD12_DXIL,
	Metal_MSL,
}

Shader_Runtime :: struct {
	backend:    Shader_Backend,
	format:     sdl.GPUShaderFormat,
	shader_dir: string,
	entrypoint: cstring,
}

init :: proc(app: ^App, title: cstring, width, height: i32) -> bool {
	if !sdl.Init({.VIDEO}) {
		fmt.eprintfln("SDL_Init failed: %s", sdl.GetError())
		return false
	}

	app.window = sdl.CreateWindow(title, width, height, {})

	if app.window == nil {
		fmt.eprintfln("CreateWindow failed: %s", sdl.GetError())
		return false
	}

	requested: sdl.GPUShaderFormat = {.SPIRV, .DXIL, .MSL}
	app.device = sdl.CreateGPUDevice(requested, true, nil)
	if app.device == nil {
		fmt.eprintfln("CreateGPUDevice failed: %s", sdl.GetError())
		return false
	}

	if !sdl.ClaimWindowForGPUDevice(app.device, app.window) {
		fmt.eprintfln("ClaimWindowForGPUDevice failed: %s", sdl.GetError())
		return false
	}

	// Prefer uncapped present for profiling; fall back if unsupported.
	present := sdl.GPUPresentMode.VSYNC
	if sdl.WindowSupportsGPUPresentMode(app.device, app.window, .IMMEDIATE) {
		present = .IMMEDIATE
	} else if sdl.WindowSupportsGPUPresentMode(app.device, app.window, .MAILBOX) {
		present = .MAILBOX
	}
	if present != .VSYNC {
		if !sdl.SetGPUSwapchainParameters(app.device, app.window, .SDR, present) {
			fmt.eprintfln("SetGPUSwapchainParameters failed: %s", sdl.GetError())
		}
	}

	ok: bool
	app.shader, ok = choose_shader_runtime(app.device)
	if !ok do return false

	app.pipeline = create_sprite_pipeline(app)
	if app.pipeline == nil {
		fmt.eprintfln("create_sprite_pipeline failed: %s", sdl.GetError())
		return false
	}

	app.sampler = sdl.CreateGPUSampler(
		app.device,
		{
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)

	if app.sampler == nil {
		fmt.eprintfln("CreateGPUSampler failed: %s", sdl.GetError())
		return false
	}

	app.vertex_buffer = sdl.CreateGPUBuffer(
		app.device,
		{usage = {.VERTEX}, size = VERTEX_BUFFER_SIZE},
	)

	if app.vertex_buffer == nil {
		fmt.eprintfln("CreateGPUBuffer failed: %s", sdl.GetError())
		return false
	}

	app.transfer_buffer = sdl.CreateGPUTransferBuffer(
		app.device,
		{usage = .UPLOAD, size = VERTEX_BUFFER_SIZE},
	)

	if app.transfer_buffer == nil {
		fmt.eprintfln("CreateGPUTransferBuffer failed: %s", sdl.GetError())
		return false
	}

	app.draw_list = make([dynamic]Queued_Sprite)

	app.camera = camera_default()

	return true
}

shutdown :: proc(app: ^App) {
	delete(app.draw_list)

	if app.device != nil {
		ok := sdl.WaitForGPUIdle(app.device)
		if !ok {
			fmt.eprintfln("WaitForGPUIdle failed")
		}

		if app.transfer_buffer != nil {
			sdl.ReleaseGPUTransferBuffer(app.device, app.transfer_buffer)
		}

		if app.vertex_buffer != nil {
			sdl.ReleaseGPUBuffer(app.device, app.vertex_buffer)
		}

		if app.sampler != nil {
			sdl.ReleaseGPUSampler(app.device, app.sampler)
		}

		if app.pipeline != nil {
			sdl.ReleaseGPUGraphicsPipeline(app.device, app.pipeline)
		}

		if app.window != nil {
			sdl.ReleaseWindowFromGPUDevice(app.device, app.window)
		}
		sdl.DestroyGPUDevice(app.device)
	}

	if app.window != nil {
		sdl.DestroyWindow(app.window)
	}

	sdl.Quit()
	app^ = {}
}

events :: proc() -> bool {
	event: sdl.Event

	for sdl.PollEvent(&event) {
		if event.type == .QUIT {
			return false
		}
	}

	return true
}

begin_frame :: proc(app: ^App, clear_color: sdl.FColor = {0.12, 0.12, 0.16, 1}) {
	clear(&app.draw_list)
	app.clear_color = clear_color
	app.render_pass = nil
	app.swapchain_texture = nil

	app.cmd = sdl.AcquireGPUCommandBuffer(app.device)
	if app.cmd == nil {
		fmt.eprintfln("AcquireGPUCommandBuffer failed: %s", sdl.GetError())
		return
	}

	ok := sdl.WaitAndAcquireGPUSwapchainTexture(
		app.cmd,
		app.window,
		&app.swapchain_texture,
		&app.swapchain_w,
		&app.swapchain_h,
	)

	if !ok || app.swapchain_texture == nil {
		app.swapchain_texture = nil
		return
	}
}

end_frame :: proc(app: ^App) {
	if app.cmd == nil {
		clear(&app.draw_list)
		return
	}

	cmd := app.cmd
	defer {
		app.render_pass = nil
		app.swapchain_texture = nil
		app.cmd = nil
		clear(&app.draw_list)
	}

	if app.swapchain_texture == nil {
		if !sdl.SubmitGPUCommandBuffer(cmd) {
			fmt.eprintfln("SubmitGPUCommandBuffer failed")
		}
		return
	}

	n := len(app.draw_list)
	if n > 0 {
		map_ptr := sdl.MapGPUTransferBuffer(app.device, app.transfer_buffer, false)
		if map_ptr == nil {
			fmt.eprintfln("MapGPUTransferBuffer failed: %s", sdl.GetError())
			if !sdl.SubmitGPUCommandBuffer(cmd) {
				fmt.eprintfln("SubmitGPUCommandBuffer failed")
			}
			return
		}

		for i in 0 ..< n {
			q := &app.draw_list[i]
			offset := i * SPRITE_VERTS_SIZE
			mem.copy(
				rawptr(uintptr(map_ptr) + uintptr(offset)),
				raw_data(q.verts[:]),
				SPRITE_VERTS_SIZE,
			)
		}
		sdl.UnmapGPUTransferBuffer(app.device, app.transfer_buffer)

		copy_pass := sdl.BeginGPUCopyPass(cmd)
		src := sdl.GPUTransferBufferLocation {
			transfer_buffer = app.transfer_buffer,
			offset          = 0,
		}
		dst := sdl.GPUBufferRegion {
			buffer = app.vertex_buffer,
			offset = 0,
			size   = u32(n * SPRITE_VERTS_SIZE),
		}
		sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
		sdl.EndGPUCopyPass(copy_pass)
	}

	color_info := sdl.GPUColorTargetInfo {
		texture     = app.swapchain_texture,
		clear_color = app.clear_color,
		load_op     = .CLEAR,
		store_op    = .STORE,
	}
	app.render_pass = sdl.BeginGPURenderPass(cmd, &color_info, 1, nil)
	sdl.BindGPUGraphicsPipeline(app.render_pass, app.pipeline)

	i := 0
	for i < n {
		run := texture_run_len(app.draw_list[:], i)
		q0 := app.draw_list[i]

		sampler_binding := sdl.GPUTextureSamplerBinding {
			texture = q0.texture,
			sampler = app.sampler,
		}
		sdl.BindGPUFragmentSamplers(app.render_pass, 0, &sampler_binding, 1)

		vb_binding := sdl.GPUBufferBinding {
			buffer = app.vertex_buffer,
			offset = u32(i * SPRITE_VERTS_SIZE),
		}
		sdl.BindGPUVertexBuffers(app.render_pass, 0, &vb_binding, 1)

		sdl.DrawGPUPrimitives(app.render_pass, u32(run * SPRITE_VERT_COUNT), 1, 0, 0)

		i += run
	}
	sdl.EndGPURenderPass(app.render_pass)
	app.render_pass = nil

	if !sdl.SubmitGPUCommandBuffer(cmd) {
		fmt.eprintfln("SubmitGPUCommandBuffer failed")
	}
}

load_gpu_shader :: proc(
	device: ^sdl.GPUDevice,
	code: []u8,
	stage: sdl.GPUShaderStage,
	format: sdl.GPUShaderFormat,
	entrypoint: cstring,
	num_samplers: u32,
) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(
		device,
		{
			code_size = len(code),
			code = raw_data(code),
			entrypoint = entrypoint,
			format = format,
			stage = stage,
			num_samplers = num_samplers,
			num_storage_textures = 0,
			num_storage_buffers = 0,
			num_uniform_buffers = 0,
		},
	)
}

shader_filenames :: proc(backend: Shader_Backend) -> (vert_name, frag_name: string) {
	switch backend {
	case .Vulkan_SPIRV:
		return "sprite.vert.spv", "sprite.frag.spv"
	case .DSD12_DXIL:
		return "sprite.vert.dxil", "sprite.frag.dxil"
	case .Metal_MSL:
		return "sprite.vert.msl", "sprite.frag.msl"
	}
	return "", ""
}

create_sprite_pipeline :: proc(app: ^App) -> ^sdl.GPUGraphicsPipeline {
	vert_name, frag_name := shader_filenames(app.shader.backend)
	vert_path, _ := filepath.join({app.shader.shader_dir, vert_name})
	frag_path, _ := filepath.join({app.shader.shader_dir, frag_name})
	defer {
		delete(vert_path)
		delete(frag_path)
	}

	vert_code, vok := load_shader_blob(vert_path)
	if !vok do return nil
	defer delete(vert_code)

	frag_code, fok := load_shader_blob(frag_path)
	if !fok do return nil
	defer delete(frag_code)

	vert := load_gpu_shader(
		app.device,
		vert_code,
		.VERTEX,
		app.shader.format,
		app.shader.entrypoint,
		0,
	)
	if vert == nil do return nil

	frag := load_gpu_shader(
		app.device,
		frag_code,
		.FRAGMENT,
		app.shader.format,
		app.shader.entrypoint,
		1,
	)
	if frag == nil {
		sdl.ReleaseGPUShader(app.device, vert)
		return nil
	}
	swap_format := sdl.GetGPUSwapchainTextureFormat(app.device, app.window)


	blend := sdl.GPUColorTargetBlendState {
		src_color_blendfactor = .SRC_ALPHA,
		dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
		color_blend_op        = .ADD,
		src_alpha_blendfactor = .ONE,
		dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
		alpha_blend_op        = .ADD,
		enable_blend          = true,
	}

	color_target := sdl.GPUColorTargetDescription {
		format      = swap_format,
		blend_state = blend,
	}

	vb_desc := sdl.GPUVertexBufferDescription {
		slot       = 0,
		pitch      = u32(size_of(Vertex)),
		input_rate = .VERTEX,
	}

	attrs := [2]sdl.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT2, offset = 0},
		{location = 1, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(Vertex, uv))},
	}

	pipeline_info := sdl.GPUGraphicsPipelineCreateInfo {
		vertex_shader = vert,
		fragment_shader = frag,
		vertex_input_state = {
			vertex_buffer_descriptions = &vb_desc,
			num_vertex_buffers = 1,
			vertex_attributes = raw_data(attrs[:]),
			num_vertex_attributes = 2,
		},
		primitive_type = .TRIANGLELIST,
		rasterizer_state = {fill_mode = .FILL},
		target_info = {color_target_descriptions = &color_target, num_color_targets = 1},
	}

	pipeline := sdl.CreateGPUGraphicsPipeline(app.device, pipeline_info)

	sdl.ReleaseGPUShader(app.device, vert)
	sdl.ReleaseGPUShader(app.device, frag)

	return pipeline
}

texture_run_len :: proc(list: []Queued_Sprite, start: int) -> int {
	if start < 0 || start >= len(list) do return 0

	tex := list[start].texture
	n := 1

	for i in start + 1 ..< len(list) {
		if list[i].texture != tex do break
		n += 1
	}

	return n
}
