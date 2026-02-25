#!/usr/bin/env bash

set -euxo pipefail

odin build . -out:wasm8 -o:speed -define:MICROUI_MAX_WIDTHS=24
