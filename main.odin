package main

import "base:runtime"

import "core:fmt"
import "core:strings"

import mu "vendor:microui"

state := struct {
	ctx:                      runtime.Context,
	mu_ctx:                   mu.Context,
	bg:                       mu.Color,
	os:                       OS,
	renderer:                 Renderer,
	cursor:                   [2]i32,
	chip8:                    Chip8,
	chip8_running:            bool,
	chip8_speed:              f32,
	chip8_timer_acc:          f32,
	chip8_rom_name:           string,
	chip8_display_rect:       mu.Rect,
	chip8_display_rect_valid: bool,
} {
	bg          = {90, 95, 100, 255},
	chip8_speed = 500,
}

main :: proc() {
	state.ctx = context

	chip8_init(&state.chip8)

	find_ibm_logo_ch8: {
		for file in ROM_FILES_CORE {
			if file.name == "ibm_logo.ch8" {
				chip8_load_rom(&state.chip8, file.data)
				state.chip8_rom_name = file.name
				state.chip8_running = true
				break find_ibm_logo_ch8
			}
		}
		panic("ibm_logo.ch8 not found")
	}

	mu.init(&state.mu_ctx, os_set_clipboard, os_get_clipboard, nil)
	state.mu_ctx.text_width = mu.default_atlas_text_width
	state.mu_ctx.text_height = mu.default_atlas_text_height

	os_init()
	r_init_and_run()
}

frame :: proc(dt: f32) {
	free_all(context.temp_allocator)

	c := &state.chip8
	if state.chip8_running {
		state.chip8_timer_acc += dt
		for state.chip8_timer_acc >= 1.0 / 60.0 {
			chip8_tick_timers(c)
			state.chip8_timer_acc -= 1.0 / 60.0
		}
		if !c.wait_key {
			steps := int(dt * state.chip8_speed)
			for _ in 0 ..< min(steps, 20) {
				if !chip8_step(c) do break
			}
		}
	}

	sound_tick(state.chip8_running ? c.sound : 0)

	mc := &state.mu_ctx

	mu.begin(mc)

	chip8_debug_windows(mc)

	mu.end(mc)

	r_render()
}

u8_slider :: proc(ctx: ^mu.Context, val: ^u8, lo, hi: u8) -> (res: mu.Result_Set) {
	mu.push_id(ctx, uintptr(val))

	@(static) tmp: mu.Real
	tmp = mu.Real(val^)
	res = mu.slider(ctx, &tmp, mu.Real(lo), mu.Real(hi), 0, "%.0f", {.ALIGN_CENTER})
	val^ = u8(tmp)
	mu.pop_id(ctx)
	return
}

number_u8 :: proc(ctx: ^mu.Context, val: ^u8, opts: mu.Options = {}, max_val: u8 = 255) -> bool {
	mu.push_id(ctx, uintptr(val))
	tmp := mu.Real(val^)
	res := mu.number(ctx, &tmp, 1, "%.0f", opts)
	if .CHANGE in res {
		val^ = u8(clamp(int(tmp), 0, int(max_val)))
		mu.pop_id(ctx)
		return true
	}
	mu.pop_id(ctx)
	return false
}

number_u16 :: proc(ctx: ^mu.Context, val: ^u16, max_val: u16, opts: mu.Options = {}) -> bool {
	mu.push_id(ctx, uintptr(val))
	tmp := mu.Real(val^)
	res := mu.number(ctx, &tmp, 1, "%.0f", opts)
	if .CHANGE in res {
		val^ = u16(clamp(int(tmp), 0, int(max_val)))
		mu.pop_id(ctx)
		return true
	}
	mu.pop_id(ctx)
	return false
}

PAD :: 8
VIEWPORT_W :: 1280
VIEWPORT_H :: 720
LEFT_W :: 280
RIGHT_W :: 360
CENTER_X :: PAD + LEFT_W + PAD
CENTER_W :: VIEWPORT_W - PAD - LEFT_W - PAD - PAD - RIGHT_W - PAD
RIGHT_X :: CENTER_X + CENTER_W + PAD
DISPLAY_H :: CENTER_W / 2
EMULATOR_H :: 286
CONTROL_H :: 130
KEYPAD_H :: EMULATOR_H - PAD - CONTROL_H
WIN_KEYS :: mu.Rect{PAD, PAD, LEFT_W, KEYPAD_H}
WIN_CONTROL :: mu.Rect{PAD, PAD + KEYPAD_H + PAD, LEFT_W, CONTROL_H}
WIN_REGISTERS :: mu.Rect {
	PAD,
	PAD + EMULATOR_H + PAD,
	LEFT_W,
	VIEWPORT_H - PAD - EMULATOR_H - PAD - PAD,
}
WIN_DISPLAY :: mu.Rect{CENTER_X, PAD, CENTER_W, DISPLAY_H}
BELOW_DISPLAY_Y :: PAD + DISPLAY_H + PAD
BELOW_DISPLAY_H :: VIEWPORT_H - BELOW_DISPLAY_Y - PAD
CENTER_BOTTOM_HALF :: (CENTER_W - PAD) / 2
WIN_STACK :: mu.Rect{CENTER_X, BELOW_DISPLAY_Y, CENTER_BOTTOM_HALF, BELOW_DISPLAY_H}
WIN_ROMS :: mu.Rect {
	CENTER_X + CENTER_BOTTOM_HALF + PAD,
	BELOW_DISPLAY_Y,
	CENTER_BOTTOM_HALF,
	BELOW_DISPLAY_H,
}
RIGHT_FILL_H :: (VIEWPORT_H - PAD - PAD - PAD) / 2
WIN_MEMORY :: mu.Rect{RIGHT_X, PAD, RIGHT_W, RIGHT_FILL_H}
WIN_DISASSEMBLY :: mu.Rect{RIGHT_X, PAD + RIGHT_FILL_H + PAD, RIGHT_W, RIGHT_FILL_H}

chip8_debug_windows :: proc(ctx: ^mu.Context) {
	opts := mu.Options{.NO_CLOSE}
	c := &state.chip8
	state.chip8_display_rect_valid = false

	if mu.window(ctx, "CHIP-8 Display", WIN_DISPLAY, opts) {
		mu.layout_row(ctx, {-1}, -1)
		r := mu.layout_next(ctx)
		state.chip8_display_rect = r
		state.chip8_display_rect_valid = true
		mu.draw_rect(ctx, r, {0, 0, 0, 255})
	}

	if mu.window(ctx, "Control", WIN_CONTROL, opts) {
		mu.layout_row(ctx, {8, 70, -1}, 0)
		marker := mu.layout_next(ctx)
		mu.draw_rect(
			ctx,
			marker,
			state.chip8_running ? mu.Color{80, 200, 80, 255} : mu.Color{120, 120, 120, 255},
		)
		mu.label(ctx, state.chip8_running ? "Running" : "Stopped")
		mu.layout_next(ctx)
		mu.layout_row(ctx, {80, 80, 80}, 0)
		if .SUBMIT in mu.button(ctx, state.chip8_running ? "Pause" : "Run") {
			state.chip8_running = !state.chip8_running
		}
		if .SUBMIT in mu.button(ctx, "Reset") {
			chip8_init(&state.chip8)
			// state.chip8_rom_name = "" // NOTE: memory isn't cleared! same ROM is still loaded.
		}
		step_opts := state.chip8_running ? mu.Options{.NO_INTERACT} : {}
		if .SUBMIT in mu.button(ctx, "Step", .NONE, step_opts) {
			chip8_step(&state.chip8)
		}
		mu.layout_row(ctx, {50, -1}, 0)
		mu.label(ctx, "Speed:")
		@(static) speed_tmp: mu.Real
		speed_tmp = mu.Real(state.chip8_speed)
		if .CHANGE in mu.slider(ctx, &speed_tmp, 100, 2000, 0, "%.0f", {.ALIGN_CENTER}) {
			state.chip8_speed = f32(speed_tmp)
		}
	}

	if mu.window(ctx, "ROMs", WIN_ROMS, opts) {
		mu.layout_row(ctx, {60, -1}, 0)
		mu.label(ctx, "Loaded:")
		mu.label(ctx, len(state.chip8_rom_name) > 0 ? state.chip8_rom_name : "(none)")
		mu.layout_row(ctx, {-1})
		for section in ROM_SECTIONS {
			if .ACTIVE in mu.header(ctx, section.name, {}) {
				for file in section.files {
					if !strings.ends_with(file.name, ".ch8") do continue
					mu.layout_row(ctx, {6, -1}, 0)
					marker := mu.layout_next(ctx)
					if file.name == state.chip8_rom_name {
						mu.draw_rect(ctx, marker, mu.Color{100, 180, 100, 255})
					}
					if .SUBMIT in mu.button(ctx, file.name[0:len(file.name) - 4]) &&
					   len(file.data) > 0 {
						chip8_load_rom(&state.chip8, file.data)
						state.chip8_rom_name = file.name
						// state.chip8_running = true
					}
				}
			}
		}
	}

	if mu.window(ctx, "Registers", WIN_REGISTERS, opts) {
		reg_opts := state.chip8_running ? mu.Options{.NO_INTERACT} : {}
		if .ACTIVE in mu.header(ctx, "V0-VF", {.EXPANDED}) {
			mu.layout_row(ctx, {36, 36, 36, 36}, 0)
			for i in 0 ..< CHIP8_REG_COUNT {
				mu.label(ctx, fmt.tprintf("V%X:", i))
				number_u8(ctx, &c.v[i], reg_opts)
				if (i + 1) % 4 == 0 do mu.layout_row(ctx, {36, 36, 36, 36}, 0)
			}
		}
		if .ACTIVE in mu.header(ctx, "Special", {.EXPANDED}) {
			mu.layout_row(ctx, {80, -1}, 0)
			mu.label(ctx, "I:")
			number_u16(ctx, &c.i, 0xFFF, reg_opts)
			mu.label(ctx, "PC:")
			number_u16(ctx, &c.pc, 0xFFF, reg_opts)
			mu.label(ctx, "SP:")
			number_u8(ctx, &c.sp, reg_opts, 15)
			mu.label(ctx, "DT:")
			number_u8(ctx, &c.delay, reg_opts)
			mu.label(ctx, "ST:")
			number_u8(ctx, &c.sound, reg_opts)
		}
	}

	if mu.window(ctx, "Memory", WIN_MEMORY, opts) {
		mu.layout_row(ctx, {-1}, -1)
		mem_opts := state.chip8_running ? mu.Options{.NO_INTERACT} : {}
		start := 0
		end := CHIP8_MEM_SIZE
		widths: [17]i32
		widths[0] = 44
		for i in 1 ..< len(widths) do widths[i] = 28
		for addr := start; addr < end; addr += 16 {
			mu.layout_row(ctx, widths[:], 0)
			mu.label(ctx, fmt.tprintf("%03X:", addr))
			n := min(16, CHIP8_MEM_SIZE - addr)
			for j in 0 ..< n {
				mu.push_id(ctx, uintptr(&c.mem[addr + j]))
				tmp := mu.Real(c.mem[addr + j])
				if .CHANGE in mu.number(ctx, &tmp, 1, "%.0f", mem_opts) {
					c.mem[addr + j] = u8(clamp(int(tmp), 0, 255))
				}
				mu.pop_id(ctx)
			}
			for _ in n ..< 16 do mu.layout_next(ctx)
		}
	}

	if mu.window(ctx, "Disassembly", WIN_DISASSEMBLY, opts) {
		mu.layout_row(ctx, {-1}, -1)
		mu.layout_row(ctx, {10, 42, -1}, 0)
		for i in 0 ..< 12 {
			addr := c.pc + u16(i * 2)
			if addr + 1 < CHIP8_MEM_SIZE {
				disasm := chip8_disasm(c, addr)
				marker_rect := mu.layout_next(ctx)
				if addr == c.pc {
					mu.draw_rect(ctx, marker_rect, mu.Color{70, 90, 120, 255})
					mu.draw_control_text(ctx, ">", marker_rect, .TEXT, {.ALIGN_CENTER})
				}
				mu.label(ctx, fmt.tprintf("%03X:", addr))
				mu.text(ctx, disasm)
			}
		}
	}

	if mu.window(ctx, "Stack", WIN_STACK, opts) {
		stack_opts := state.chip8_running ? mu.Options{.NO_INTERACT} : {}
		mu.layout_row(ctx, {40, -1}, 0)
		for i in 0 ..< CHIP8_STACK_SIZE {
			mu.label(ctx, fmt.tprintf("[%d]", i))
			if i < int(c.sp) {
				number_u16(ctx, &c.stack[i], 0xFFFF, stack_opts)
			} else {
				mu.label(ctx, "-")
			}
		}
	}

	if mu.window(ctx, "Keypad", WIN_KEYS, opts) {
			// odinfmt: disable
		labels := [16]string {
			"1", "2", "3", "C",
			"4", "5", "6", "D",
			"7", "8", "9", "E",
			"A", "0", "B", "F",
		}
		keypad_indices := [16]u8{
			0x1, 0x2, 0x3, 0xC,
			0x4, 0x5, 0x6, 0xD,
			0x7, 0x8, 0x9, 0xE,
			0xA, 0x0, 0xB, 0xF,
		}
		// odinfmt: enable
		mu.layout_row(ctx, {36, 36, 36, 36}, 0)
		for i in 0 ..< 16 {
			r := mu.layout_next(ctx)
			clr :=
				c.keys[keypad_indices[i]] ? mu.Color{100, 200, 100, 255} : ctx.style.colors[.BASE]
			mu.draw_rect(ctx, r, clr)
			mu.draw_control_text(ctx, labels[i], r, .TEXT, {.ALIGN_CENTER})
		}
	}
}
