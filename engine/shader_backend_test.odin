package engine

import "core:testing"
import sdl "vendor:sdl3"

@(test)
shader_filenames_per_backend :: proc(t: ^testing.T) {
	vert, frag := shader_filenames(.Vulkan_SPIRV)
	testing.expect_value(t, vert, "sprite.vert.spv")
	testing.expect_value(t, frag, "sprite.frag.spv")

	vert, frag = shader_filenames(.DSD12_DXIL)
	testing.expect_value(t, vert, "sprite.vert.dxil")
	testing.expect_value(t, frag, "sprite.frag.dxil")

	vert, frag = shader_filenames(.Metal_MSL)
	testing.expect_value(t, vert, "sprite.vert.msl")
	testing.expect_value(t, frag, "sprite.frag.msl")
}

@(test)
choose_shader_runtime_prefers_msl :: proc(t: ^testing.T) {
	rt, ok := choose_shader_runtime_from_formats({.MSL, .SPIRV, .DXIL})
	testing.expect(t, ok)
	testing.expect_value(t, rt.backend, Shader_Backend.Metal_MSL)
	testing.expect_value(t, rt.shader_dir, "shaders/metal")
	testing.expect_value(t, rt.format, sdl.GPUShaderFormat{.MSL})
}

@(test)
choose_shader_runtime_spirv_only :: proc(t: ^testing.T) {
	rt, ok := choose_shader_runtime_from_formats({.SPIRV})
	testing.expect(t, ok)
	testing.expect_value(t, rt.backend, Shader_Backend.Vulkan_SPIRV)
	testing.expect_value(t, rt.shader_dir, "shaders/vulkan")
	testing.expect_value(t, rt.format, sdl.GPUShaderFormat{.SPIRV})
}

@(test)
choose_shader_runtime_empty_fails :: proc(t: ^testing.T) {
	_, ok := choose_shader_runtime_from_formats({})
	testing.expect(t, !ok)
}
