#!/bin/sh
echo -ne '\033c\033]0;catsimulator2026\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/realnicosimulator2026 -linux.x86_64" "$@"
