package engine

import "core:fmt"
import "core:path/filepath"
import sdl "vendor:sdl3"

Vertex :: struct {
	pos: [2]f32, // clip space, -1..1
	uv:  [2]f32, // 0..1 atlas coords (used later in draw_sprite)
}

SPRITE_VERT_COUNT :: 6
VERTEX_BUFFER_SIZE :: SPRITE_VERT_COUNT * size_of(Vertex)

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

	return true
}

shutdown :: proc(app: ^App) {
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

begin_frame :: proc(app: ^App, clear: sdl.FColor = {0.12, 0.12, 0.16, 1}) {
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
		return
	}

	color_info := sdl.GPUColorTargetInfo {
		texture     = app.swapchain_texture,
		clear_color = clear,
		load_op     = .CLEAR,
		store_op    = .STORE,
	}

	app.render_pass = sdl.BeginGPURenderPass(app.cmd, &color_info, 1, nil)

	sdl.BindGPUGraphicsPipeline(app.render_pass, app.pipeline)
}

end_frame :: proc(app: ^App) {
	if app.render_pass != nil {
		sdl.EndGPURenderPass(app.render_pass)
		app.render_pass = nil
	}

	if app.cmd != nil {
		ok := sdl.SubmitGPUCommandBuffer(app.cmd)
		if !ok {
			fmt.eprintfln("SubmitGPUCommandBuffer failed")
		}
		app.cmd = nil
	}

	app.swapchain_texture = nil
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
