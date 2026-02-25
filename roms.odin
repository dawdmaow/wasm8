package main

import "base:runtime"
import "core:strings"

ROM_Section :: struct {
	name:  string,
	files: []runtime.Load_Directory_File,
}

ROM_FILES_CORE := #load_directory("roms")
ROM_FILES_TEST_SUITE := #load_directory("roms/chip8-test-suite")
ROM_FILES_DEMOS := #load_directory("roms/demos")
ROM_FILES_GAMES := #load_directory("roms/games")
ROM_FILES_HIRES := #load_directory("roms/hires")
ROM_FILES_PROGRAMS := #load_directory("roms/programs")
ROM_SECTIONS := [?]ROM_Section {
	{"Core", ROM_FILES_CORE[:]},
	{"Tests", ROM_FILES_TEST_SUITE[:]},
	{"Demos", ROM_FILES_DEMOS[:]},
	{"Games", ROM_FILES_GAMES[:]},
	{"Hires", ROM_FILES_HIRES[:]},
	{"Programs", ROM_FILES_PROGRAMS[:]},
}

get_embedded_rom :: proc(name: string, buf: []byte) -> int {
	for section in ROM_SECTIONS {
		for &file in section.files {
			if strings.to_lower(file.name) == strings.to_lower(name) {
				n := min(len(file.data), len(buf))
				copy(buf[:n], file.data)
				return n
			}
		}
	}
	return 0
}
