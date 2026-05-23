#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_script="$script_dir/photos2pdf.sh"
target_dir="${HOME}/.local/bin"
target_link="$target_dir/photos2pdf"

if [ ! -f "$source_script" ]; then
  printf 'Error: source script not found: %s\n' "$source_script" >&2
  exit 1
fi

mkdir -p "$target_dir"
chmod +x "$source_script"
ln -sfn "$source_script" "$target_link"

printf 'Installed: %s -> %s\n' "$target_link" "$source_script"

case ":$PATH:" in
  *":$target_dir:"*)
    ;;
  *)
    printf 'Note: %s is not currently on PATH in this shell.\n' "$target_dir"
    printf 'Open a new shell or add it to PATH before using `photos2pdf`.\n'
    ;;
esac
