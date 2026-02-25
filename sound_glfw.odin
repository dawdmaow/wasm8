#+build !js
package main

import "core:mem"
import ma "vendor:miniaudio"

SAMPLE_RATE :: 44100
BEEP_FREQ :: 440.0

@(private = "file")
sound_active: u8 = 0
@(private = "file")
phase: f32 = 0
@(private = "file")
device: ma.device

@(private = "file")
data_callback :: proc "c" (
	p_device: ^ma.device,
	p_output: rawptr,
	p_input: rawptr,
	frame_count: u32,
) {
	output := mem.slice_ptr(cast(^f32)p_output, int(frame_count) * 2)
	step := BEEP_FREQ / f32(SAMPLE_RATE)
	for i in 0 ..< frame_count {
		sample: f32 = 0
		if sound_active > 0 {
			sample = (phase < 0.5 ? 0.15 : -0.15)
			phase += step
			for phase >= 1.0 do phase -= 1.0
		}
		output[i * 2 + 0] = sample
		output[i * 2 + 1] = sample
	}
}

sound_tick_impl :: proc(timer: u8) {
	sound_active = timer
	if timer > 0 && ma.device_is_started(&device) == false {
		ma.device_start(&device)
	} else if timer == 0 && ma.device_is_started(&device) {
		ma.device_stop(&device)
	}
}

sound_init :: proc() {
	config := ma.device_config_init(ma.device_type.playback)
	config.playback.format = ma.format.f32
	config.playback.channels = 2
	config.sampleRate = SAMPLE_RATE
	config.dataCallback = data_callback
	if ma.device_init(nil, &config, &device) != ma.result.SUCCESS {
		return
	}
}
