package engine

import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

choose_shader_runtime_from_formats :: proc(
	supported: sdl.GPUShaderFormat,
) -> (
	Shader_Runtime,
	bool,
) {
	if .MSL in supported {
		return {
			backend = .Metal_MSL,
			format = {.MSL},
			shader_dir = "shaders/metal",
			entrypoint = "main",
		}, true
	}
	if .DXIL in supported {
		return {
			backend = .DSD12_DXIL,
			format = {.DXIL},
			shader_dir = "shaders/d3d12",
			entrypoint = "main",
		}, true
	}
	if .SPIRV in supported {
		return {
			backend = .Vulkan_SPIRV,
			format = {.SPIRV},
			shader_dir = "shaders/vulkan",
			entrypoint = "main",
		}, true
	}

	fmt.eprintfln("No supported shader format from device (got %v)", supported)
	return {}, false
}

choose_shader_runtime :: proc(device: ^sdl.GPUDevice) -> (Shader_Runtime, bool) {
	supported := sdl.GetGPUShaderFormats(device)
	return choose_shader_runtime_from_formats(supported)
}

load_shader_blob :: proc(path: string) -> ([]u8, bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("failed to read shader %s: %v", path, err)
		return nil, false
	}

	return data, true
}
