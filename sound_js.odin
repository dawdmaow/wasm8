#+build js
package main

foreign import chip8_sound "chip8_sound"
foreign chip8_sound {
	chip8_sound_set_timer :: proc "c" (value: i32) ---
}

sound_tick_impl :: proc(timer: u8) {
	chip8_sound_set_timer(i32(timer))
}
