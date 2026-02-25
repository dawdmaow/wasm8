package main

import "core:fmt"
import "core:math/rand"
import "core:mem"

CHIP8_MEM_SIZE :: 4096
CHIP8_PROG_START :: 0x200
CHIP8_DISPLAY_W :: 64
CHIP8_DISPLAY_H :: 32
CHIP8_DISPLAY_SIZE :: CHIP8_DISPLAY_W * CHIP8_DISPLAY_H
CHIP8_STACK_SIZE :: 16
CHIP8_REG_COUNT :: 16

Chip8_Platform :: enum {
	Chip8,
}

// odinfmt: disable
CHIP8_FONT :: [80]u8 {
	0xF0, 0x90, 0x90, 0x90, 0xF0,
	0x20, 0x60, 0x20, 0x20, 0x70,
	0xF0, 0x10, 0xF0, 0x80, 0xF0,
	0xF0, 0x10, 0xF0, 0x10, 0xF0,
	0x90, 0x90, 0xF0, 0x10, 0x10,
	0xF0, 0x80, 0xF0, 0x10, 0xF0,
	0xF0, 0x80, 0xF0, 0x90, 0xF0,
	0xF0, 0x10, 0x20, 0x40, 0x40,
	0xF0, 0x90, 0xF0, 0x90, 0xF0,
	0xF0, 0x90, 0xF0, 0x10, 0xF0,
	0xF0, 0x90, 0xF0, 0x90, 0x90,
	0xE0, 0x90, 0xE0, 0x90, 0xE0,
	0xF0, 0x80, 0x80, 0x80, 0xF0,
	0xE0, 0x90, 0x90, 0x90, 0xE0,
	0xF0, 0x80, 0xF0, 0x80, 0xF0,
	0xF0, 0x80, 0xF0, 0x80, 0x80,
}
// odinfmt: enable

Chip8 :: struct {
	platform:     Chip8_Platform,
	mem:          [CHIP8_MEM_SIZE]u8,
	v:            [CHIP8_REG_COUNT]u8,
	i:            u16,
	pc:           u16,
	sp:           u8,
	stack:        [CHIP8_STACK_SIZE]u16,
	delay:        u8,
	sound:        u8,
	display:      [CHIP8_DISPLAY_SIZE]bool,
	keys:         [16]bool,
	wait_key:     bool,
	wait_reg:     u8,
	key_received: bool,
	pending_key:  u8,
}

CHIP8_FONT_ADDR :: 0x50

chip8_init :: proc(c: ^Chip8) {
	// NOTE: We intentioally don't clear memory - this should only reset state without requiring a reload of the current ROM.
	c.platform = .Chip8
	font := CHIP8_FONT
	for i in 0 ..< len(font) {
		c.mem[CHIP8_FONT_ADDR + i] = font[i]
	}
	c.v = {}
	c.i = 0
	c.stack = {}
	c.pc = CHIP8_PROG_START
	c.sp = 0
	c.delay = 0
	c.sound = 0
	c.display = {}
	c.keys = {}
	c.wait_key = false
	c.wait_reg = 0
	c.key_received = false
	c.pending_key = 16
}

chip8_load_rom :: proc(c: ^Chip8, data: []byte) -> bool {
	invalid_rom := len(data) == 0 || len(data) > CHIP8_MEM_SIZE - CHIP8_PROG_START
	if invalid_rom {
		return false
	}
	mem.zero_slice(c.mem[CHIP8_PROG_START:])
	copy(c.mem[CHIP8_PROG_START:], data)
	chip8_init(c)
	return true
}

chip8_key_down :: proc(c: ^Chip8, key: u8) {
	if key < 16 {
		c.keys[key] = true
		if c.wait_key && c.wait_reg < 16 && c.pending_key > 15 {
			c.pending_key = key
		}
	}
}

chip8_key_up :: proc(c: ^Chip8, key: u8) {
	if key < 16 {
		c.keys[key] = false
		if c.wait_key && c.wait_reg < 16 && c.pending_key == key {
			c.v[c.wait_reg] = key
			c.wait_key = false
			c.key_received = true
			c.pending_key = 16
		}
	}
}

chip8_tick_timers :: proc(c: ^Chip8) {
	if c.delay > 0 {
		c.delay -= 1
	}
	if c.sound > 0 {
		c.sound -= 1
	}
}

chip8_draw_sprite :: proc(c: ^Chip8, x, y: u8, n: u8) -> (collision: bool) {
	base_x := int(x % CHIP8_DISPLAY_W)
	base_y := int(y % CHIP8_DISPLAY_H)
	for row in 0 ..< n {
		addr := c.i + u16(row)
		if addr >= CHIP8_MEM_SIZE do continue
		byte := c.mem[addr]
		py := base_y + int(row)
		for col in 0 ..< 8 {
			px := base_x + int(col)
			if px < 0 || px >= CHIP8_DISPLAY_W || py < 0 || py >= CHIP8_DISPLAY_H do continue
			idx := py * CHIP8_DISPLAY_W + px
			bit := (byte >> u32(7 - col)) & 1
			prev := c.display[idx]
			c.display[idx] = prev != (bit != 0)
			if prev && c.display[idx] == false {
				collision = true
			}
		}
	}
	return
}

chip8_disasm :: proc(c: ^Chip8, addr: u16) -> string {
	if addr + 1 >= CHIP8_MEM_SIZE do return "???"
	op := (u16(c.mem[addr]) << 8) | u16(c.mem[addr + 1])
	nnn := op & 0x0FFF
	nn := u8(op & 0x00FF)
	x := u8((op >> 8) & 0x0F)
	y := u8((op >> 4) & 0x0F)
	n := u8(op & 0x000F)
	switch op >> 12 {
	case 0:
		switch op {
		case 0x00E0:
			return "CLS"
		case 0x00EE:
			return "RET"
		case:
			return fmt.tprintf("SYS 0x%03X", nnn)
		}
	case 1:
		return fmt.tprintf("JP 0x%03X", nnn)
	case 2:
		return fmt.tprintf("CALL 0x%03X", nnn)
	case 3:
		return fmt.tprintf("SE V%X, 0x%02X", x, nn)
	case 4:
		return fmt.tprintf("SNE V%X, 0x%02X", x, nn)
	case 5:
		return fmt.tprintf("SE V%X, V%X", x, y)
	case 6:
		return fmt.tprintf("LD V%X, 0x%02X", x, nn)
	case 7:
		return fmt.tprintf("ADD V%X, 0x%02X", x, nn)
	case 8:
		switch n {
		case 0:
			return fmt.tprintf("LD V%X, V%X", x, y)
		case 1:
			return fmt.tprintf("OR V%X, V%X", x, y)
		case 2:
			return fmt.tprintf("AND V%X, V%X", x, y)
		case 3:
			return fmt.tprintf("XOR V%X, V%X", x, y)
		case 4:
			return fmt.tprintf("ADD V%X, V%X", x, y)
		case 5:
			return fmt.tprintf("SUB V%X, V%X", x, y)
		case 6:
			return fmt.tprintf("SHR V%X", x)
		case 7:
			return fmt.tprintf("SUBN V%X, V%X", x, y)
		case 0xE:
			return fmt.tprintf("SHL V%X", x)
		case:
			return "???"
		}
	case 9:
		return fmt.tprintf("SNE V%X, V%X", x, y)
	case 0xA:
		return fmt.tprintf("LD I, 0x%03X", nnn)
	case 0xB:
		return fmt.tprintf("JP V0, 0x%03X", nnn)
	case 0xC:
		return fmt.tprintf("RND V%X, 0x%02X", x, nn)
	case 0xD:
		return fmt.tprintf("DRW V%X, V%X, %d", x, y, n)
	case 0xE:
		switch nn {
		case 0x9E:
			return fmt.tprintf("SKP V%X", x)
		case 0xA1:
			return fmt.tprintf("SKNP V%X", x)
		case:
			return "???"
		}
	case 0xF:
		switch nn {
		case 0x07:
			return fmt.tprintf("LD V%X, DT", x)
		case 0x0A:
			return fmt.tprintf("LD V%X, K", x)
		case 0x15:
			return fmt.tprintf("LD DT, V%X", x)
		case 0x18:
			return fmt.tprintf("LD ST, V%X", x)
		case 0x1E:
			return fmt.tprintf("ADD I, V%X", x)
		case 0x29:
			return fmt.tprintf("LD F, V%X", x)
		case 0x33:
			return fmt.tprintf("LD B, V%X", x)
		case 0x55:
			return fmt.tprintf("LD [I], V%X", x)
		case 0x65:
			return fmt.tprintf("LD V%X, [I]", x)
		case:
			return "???"
		}
	case:
		return "???"
	}
	return "???"
}

chip8_step :: proc(c: ^Chip8) -> bool {
	if c.wait_key do return false
	if c.pc + 1 >= CHIP8_MEM_SIZE do return false

	op := (u16(c.mem[c.pc]) << 8) | u16(c.mem[c.pc + 1])
	c.pc += 2

	nnn := op & 0x0FFF
	nn := u8(op & 0x00FF)
	x := u8((op >> 8) & 0x0F)
	y := u8((op >> 4) & 0x0F)
	n := u8(op & 0x000F)

	switch op >> 12 {
	case 0:
		switch op {
		case 0x00E0:
			// CLS
			c.display = {}
		case 0x00EE:
			// RET
			if c.sp > 0 {
				c.sp -= 1
				c.pc = c.stack[c.sp]
			}
		case: // SYS - ignored
		}
	case 1:
		// JP
		c.pc = nnn
	case 2:
		// CALL
		if c.sp < CHIP8_STACK_SIZE {
			c.stack[c.sp] = c.pc
			c.sp += 1
			c.pc = nnn
		}
	case 3:
		// SE Vx, nn
		if c.v[x] == nn do c.pc += 2
	case 4:
		// SNE Vx, nn
		if c.v[x] != nn do c.pc += 2
	case 5:
		// SE Vx, Vy
		if c.v[x] == c.v[y] do c.pc += 2
	case 6:
		// LD Vx, nn
		c.v[x] = nn
	case 7:
		// ADD Vx, nn
		c.v[x] += nn
	case 8:
		switch n {
		case 0:
			// LD
			c.v[x] = c.v[y]
		case 1:
			// OR
			c.v[x] |= c.v[y]
			c.v[0xF] = 0
		case 2:
			// AND
			c.v[x] &= c.v[y]
			c.v[0xF] = 0
		case 3:
			// XOR
			c.v[x] ~= c.v[y]
			c.v[0xF] = 0
		case 4:
			// ADD
			vx, vy := c.v[x], c.v[y]
			sum := u16(vx) + u16(vy)
			carry := sum > 255 ? u8(1) : u8(0)
			if x == 0xF {
				c.v[0xF] = carry
			} else {
				c.v[x] = u8(sum)
				c.v[0xF] = carry
			}
		case 5:
			// SUB
			vx, vy := c.v[x], c.v[y]
			flag := vx >= vy ? u8(1) : u8(0)
			if x == 0xF {
				c.v[0xF] = flag
			} else {
				c.v[x] = vx - vy
				c.v[0xF] = flag
			}
		case 6:
			// SHR
			vy := c.v[y]
			flag := vy & 1
			if x == 0xF {
				c.v[0xF] = flag
			} else {
				c.v[x] = vy >> 1
				c.v[0xF] = flag
			}
		case 7:
			// SUBN
			vx, vy := c.v[x], c.v[y]
			flag := vy >= vx ? u8(1) : u8(0)
			if x == 0xF {
				c.v[0xF] = flag
			} else {
				c.v[x] = vy - vx
				c.v[0xF] = flag
			}
		case 0xE:
			// SHL
			vy := c.v[y]
			flag := (vy >> 7) & 1
			if x == 0xF {
				c.v[0xF] = flag
			} else {
				c.v[x] = vy << 1
				c.v[0xF] = flag
			}
		}
	case 9:
		// SNE Vx, Vy
		if c.v[x] != c.v[y] do c.pc += 2
	case 0xA:
		// LD I, nnn
		c.i = nnn
	case 0xB:
		// JP V0, nnn
		c.pc = nnn + u16(c.v[0])
	case 0xC:
		// RND
		c.v[x] = u8(rand.uint32() & 0xFF) & nn
	case 0xD:
		// DRW
		c.v[0xF] = chip8_draw_sprite(c, c.v[x], c.v[y], n) ? 1 : 0
	case 0xE:
		switch nn {
		case 0x9E:
			// SKP
			if c.v[x] < 16 && c.keys[c.v[x]] do c.pc += 2
		case 0xA1:
			// SKNP
			if c.v[x] >= 16 || !c.keys[c.v[x]] do c.pc += 2
		}
	case 0xF:
		switch nn {
		case 0x07:
			// LD Vx, DT
			c.v[x] = c.delay
		case 0x0A:
			// LD Vx, K
			if c.key_received {
				c.key_received = false
			} else {
				c.wait_key = true
				c.wait_reg = x
				c.pc -= 2
			}
		case 0x15:
			// LD DT, Vx
			c.delay = c.v[x]
		case 0x18:
			// LD ST, Vx
			c.sound = c.v[x]
		case 0x1E:
			// ADD I, Vx
			c.i += u16(c.v[x])
		case 0x29:
			// LD F, Vx
			c.i = 0x50 + u16(c.v[x]) * 5
		case 0x33:
			// LD B, Vx
			val := c.v[x]
			c.mem[c.i + 0] = val / 100
			c.mem[c.i + 1] = (val / 10) % 10
			c.mem[c.i + 2] = val % 10
		case 0x55:
			// LD [I], Vx
			for i in 0 ..= x {
				if c.i + u16(i) < CHIP8_MEM_SIZE {
					c.mem[c.i + u16(i)] = c.v[i]
				}
			}
			c.i += u16(x) + 1
		case 0x65:
			// LD Vx, [I]
			for i in 0 ..= x {
				if c.i + u16(i) < CHIP8_MEM_SIZE {
					c.v[i] = c.mem[c.i + u16(i)]
				}
			}
			c.i += u16(x) + 1
		}
	}
	return true
}
