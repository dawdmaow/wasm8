#+build !js
package main

import "core:log"
import "core:math"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

import "vendor:glfw"
import mu "vendor:microui"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

OS :: struct {
	window: glfw.WindowHandle,
}

GLFW_WINDOW_WIDTH :: 1280
GLFW_WINDOW_HEIGHT :: 720
GLFW_WINDOW_TITLE :: "CHIP-8"

os_init :: proc() {
	if !glfw.Init() {
		panic("[glfw] init failure")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	state.os.window = glfw.CreateWindow(
		GLFW_WINDOW_WIDTH,
		GLFW_WINDOW_HEIGHT,
		GLFW_WINDOW_TITLE,
		nil,
		nil,
	)
	assert(state.os.window != nil)

	glfw.SetKeyCallback(state.os.window, key_callback)
	glfw.SetMouseButtonCallback(state.os.window, mouse_button_callback)
	glfw.SetCursorPosCallback(state.os.window, cursor_pos_callback)
	glfw.SetScrollCallback(state.os.window, scroll_callback)
	glfw.SetCharCallback(state.os.window, char_callback)
	glfw.SetFramebufferSizeCallback(state.os.window, size_callback)

	sound_init()
}

os_run :: proc() {
	for !glfw.WindowShouldClose(state.os.window) {
		glfw.PollEvents()
		do_frame()
	}

	glfw.DestroyWindow(state.os.window)
	glfw.Terminate()
}

@(private = "file")
do_frame :: proc() {
	@(static) frame_time: time.Tick
	if frame_time == {} {
		frame_time = time.tick_now()
	}

	new_frame_time := time.tick_now()
	dt := time.tick_diff(frame_time, new_frame_time)
	frame_time = new_frame_time

	frame(f32(time.duration_seconds(dt)))
}

os_get_render_bounds :: proc() -> (width, height: u32) {
	iw, ih := glfw.GetFramebufferSize(state.os.window)
	return u32(iw), u32(ih)
}

os_get_dpi :: proc() -> f32 {
	sw, sh := glfw.GetWindowContentScale(state.os.window)
	if sw != sh {
		log.warnf("dpi x (%v) and y (%v) not the same", sw, sh)
	}
	return sw
}

os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return glfwglue.GetSurface(instance, state.os.window)
}

os_set_clipboard :: proc(_: rawptr, text: string) -> bool {
	glfw.SetClipboardString(
		state.os.window,
		strings.clone_to_cstring(text, context.temp_allocator),
	)
	return true
}

os_get_clipboard :: proc(_: rawptr) -> (string, bool) {
	clipboard := glfw.GetClipboardString(state.os.window)
	return clipboard, true
}

@(private = "file")
chip8_key_from_glfw :: proc(key: i32) -> (u8, bool) {
	switch key {
	case glfw.KEY_1:
		return 0x1, true
	case glfw.KEY_2:
		return 0x2, true
	case glfw.KEY_3:
		return 0x3, true
	case glfw.KEY_4:
		return 0xC, true
	case glfw.KEY_Q:
		return 0x4, true
	case glfw.KEY_W:
		return 0x5, true
	case glfw.KEY_E:
		return 0x6, true
	case glfw.KEY_R:
		return 0xD, true
	case glfw.KEY_A:
		return 0x7, true
	case glfw.KEY_S:
		return 0x8, true
	case glfw.KEY_D:
		return 0x9, true
	case glfw.KEY_F:
		return 0xE, true
	case glfw.KEY_Z:
		return 0xA, true
	case glfw.KEY_X:
		return 0x0, true
	case glfw.KEY_C:
		return 0xB, true
	case glfw.KEY_V:
		return 0xF, true
	case:
		return 0, false
	}
}

@(private = "file")
key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = state.ctx

	if state.chip8_running {
		if ck, ok := chip8_key_from_glfw(key); ok {
			switch action {
			case glfw.PRESS, glfw.REPEAT:
				chip8_key_down(&state.chip8, ck)
			case glfw.RELEASE:
				chip8_key_up(&state.chip8, ck)
			}
		}
	}

	mu_key: mu.Key

	switch key {
	case glfw.KEY_LEFT_SHIFT, glfw.KEY_RIGHT_SHIFT:
		mu_key = .SHIFT
	case glfw.KEY_LEFT_CONTROL, glfw.KEY_RIGHT_CONTROL, glfw.KEY_LEFT_SUPER, glfw.KEY_RIGHT_SUPER:
		mu_key = .CTRL
	case glfw.KEY_LEFT_ALT, glfw.KEY_RIGHT_ALT:
		mu_key = .ALT
	case glfw.KEY_BACKSPACE:
		mu_key = .BACKSPACE
	case glfw.KEY_DELETE:
		mu_key = .DELETE
	case glfw.KEY_ENTER:
		mu_key = .RETURN
	case glfw.KEY_LEFT:
		mu_key = .LEFT
	case glfw.KEY_RIGHT:
		mu_key = .RIGHT
	case glfw.KEY_HOME:
		mu_key = .HOME
	case glfw.KEY_END:
		mu_key = .END
	case glfw.KEY_A:
		mu_key = .A
	case glfw.KEY_X:
		mu_key = .X
	case glfw.KEY_C:
		mu_key = .C
	case glfw.KEY_V:
		mu_key = .V
	case:
		return
	}

	switch action {
	case glfw.PRESS, glfw.REPEAT:
		mu.input_key_down(&state.mu_ctx, mu_key)
	case glfw.RELEASE:
		mu.input_key_up(&state.mu_ctx, mu_key)
	case:
		return
	}
}

@(private = "file")
mouse_button_callback :: proc "c" (window: glfw.WindowHandle, key, action, mods: i32) {
	context = state.ctx

	mu_key: mu.Mouse; switch key {
	case glfw.MOUSE_BUTTON_MIDDLE:
		mu_key = .MIDDLE
	case glfw.MOUSE_BUTTON_LEFT:
		mu_key = .LEFT
	case glfw.MOUSE_BUTTON_RIGHT:
		mu_key = .RIGHT
	}

	switch action {
	case glfw.PRESS, glfw.REPEAT:
		mu.input_mouse_down(&state.mu_ctx, state.cursor.x, state.cursor.y, mu_key)
	case glfw.RELEASE:
		mu.input_mouse_up(&state.mu_ctx, state.cursor.x, state.cursor.y, mu_key)
	}
}

@(private = "file")
cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
	context = state.ctx
	state.cursor = {i32(math.round(x)), i32(math.round(y))}
	mu.input_mouse_move(&state.mu_ctx, state.cursor.x, state.cursor.y)
}

@(private = "file")
scroll_callback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
	context = state.ctx
	mu.input_scroll(&state.mu_ctx, -i32(math.round(x)), -i32(math.round(y)))
}

@(private = "file")
char_callback :: proc "c" (window: glfw.WindowHandle, ch: rune) {
	context = state.ctx
	bytes, size := utf8.encode_rune(ch)
	mu.input_text(&state.mu_ctx, string(bytes[:size]))
}

@(private = "file")
size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	context = state.ctx
	r_resize()
	do_frame()
}
