#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./photos2pdf.sh [options] [INPUT_DIR] [OUTPUT_PDF]

Convert a directory of JPG/JPEG photos into a cleaned PDF.
By default each input image is treated as a left/right two-page spread.
Use --layout 1 for single-page photos.

Options:
  --layout N                   Page layout per image: 1 (single page) or
                               2 (two-page spread). Default: 2
  --dpi N                      Input and output DPI for ScanTailor. Default: 300
  --margin N                   Whitespace margin to preserve around each page.
                               Default: 30
  --dewarping MODE             ScanTailor dewarping mode. Default: auto
                               Allowed values: auto, off
  --dewarp-off-image NAME      Reprocess one source image with dewarping off
                               after the main pass. Repeat for multiple files.
  --depth-perception N         ScanTailor dewarping depth. Default: 2.0
  --binarize                   Convert cleaned pages to pure black/white using
                               a per-page mean threshold. On by default.
  --no-binarize                Skip the final black/white conversion step.
  --binarize-threshold-offset N
                               Offset added to the per-page mean threshold in
                               percent. Default: 0
  --color-mode MODE            ScanTailor color mode. Default: color_grayscale
                               Allowed values include: black_and_white,
                               color_grayscale, mixed
  --work-dir DIR               Working directory for ScanTailor project/pages.
                               Default: a new temporary directory
  --normalize-illumination     Enable ScanTailor illumination normalization.
                               On by default.
  --no-normalize-illumination  Disable ScanTailor illumination normalization.
  --cleanup                    Remove the work directory after a successful run.
  --force                      Overwrite existing output PDF and re-create the
                               generated ScanTailor work products.
  -h, --help                   Show this help text.

Examples:
  ./photos2pdf.sh
  ./photos2pdf.sh --layout 1 "/path/to/single-page-photos"
  ./photos2pdf.sh "/path/to/book-photos"
  ./photos2pdf.sh --dewarp-off-image IMG_0720.JPG --dewarp-off-image IMG_0723.JPG
  ./photos2pdf.sh --binarize-threshold-offset 0.5 "/path/to/book-photos"
  ./photos2pdf.sh --margin 40 "/path/to/book-photos" "/path/to/output/book.pdf"
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

assemble_pdf() {
  local output_pdf=$1
  shift

  if command -v convert >/dev/null 2>&1; then
    convert "$@" -compress zip "$output_pdf"
    return
  fi

  if command -v magick >/dev/null 2>&1; then
    magick "$@" -compress zip "$output_pdf"
    return
  fi

  die "Need either ImageMagick 'convert' or 'magick' to assemble the final PDF"
}

join_by() {
  local delimiter=$1
  shift
  local first=1
  for item in "$@"; do
    if ((first)); then
      printf '%s' "$item"
      first=0
    else
      printf '%s%s' "$delimiter" "$item"
    fi
  done
}

threshold_image_to_bilevel() {
  local src=$1
  local dest=$2
  local threshold_offset=$3

  local mean threshold
  mean=$(identify -format '%[fx:100*mean]' "$src")
  threshold=$(awk -v m="$mean" -v o="$threshold_offset" 'BEGIN {
    t = m + o
    if (t < 0) t = 0
    if (t > 100) t = 100
    printf "%.4f", t
  }')

  convert "$src" -colorspace Gray -threshold "${threshold}%" -compress group4 "$dest"
}

dpi=300
margin=30
layout=2
dewarping=auto
depth_perception=2.0
binarize=1
binarize_threshold_offset=0
color_mode=color_grayscale
normalize_illumination=1
cleanup=0
force=0
work_dir=
work_dir_is_temp=0
dewarp_off_images=()

while (($#)); do
  case "$1" in
    --layout)
      (($# >= 2)) || die "--layout requires a value"
      layout=$2
      shift 2
      ;;
    --dpi)
      (($# >= 2)) || die "--dpi requires a value"
      dpi=$2
      shift 2
      ;;
    --margin)
      (($# >= 2)) || die "--margin requires a value"
      margin=$2
      shift 2
      ;;
    --dewarping)
      (($# >= 2)) || die "--dewarping requires a value"
      dewarping=$2
      shift 2
      ;;
    --dewarp-off-image)
      (($# >= 2)) || die "--dewarp-off-image requires a value"
      dewarp_off_images+=("$2")
      shift 2
      ;;
    --depth-perception)
      (($# >= 2)) || die "--depth-perception requires a value"
      depth_perception=$2
      shift 2
      ;;
    --binarize)
      binarize=1
      shift
      ;;
    --no-binarize)
      binarize=0
      shift
      ;;
    --binarize-threshold-offset)
      (($# >= 2)) || die "--binarize-threshold-offset requires a value"
      binarize_threshold_offset=$2
      shift 2
      ;;
    --color-mode)
      (($# >= 2)) || die "--color-mode requires a value"
      color_mode=$2
      shift 2
      ;;
    --work-dir)
      (($# >= 2)) || die "--work-dir requires a value"
      work_dir=$2
      shift 2
      ;;
    --normalize-illumination)
      normalize_illumination=1
      shift
      ;;
    --no-normalize-illumination)
      normalize_illumination=0
      shift
      ;;
    --cleanup)
      cleanup=1
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

if (($# >= 1)) && [ -d "$1" ]; then
  input_dir=$1
  shift
else
  input_dir=.
fi

if [ -d "$input_dir" ]; then
  input_dir=$(cd "$input_dir" && pwd)
else
  die "Input directory does not exist: $input_dir"
fi

if (($# >= 1)); then
  output_pdf=$1
  shift
else
  output_pdf="$input_dir/$(basename "$input_dir").pdf"
fi

(($# == 0)) || die "Too many positional arguments"

need_cmd scantailor-universal-cli
need_cmd find
need_cmd sort

case "$dewarping" in
  auto|off)
    ;;
  *)
    die "Unsupported --dewarping mode: $dewarping"
    ;;
esac

case "$layout" in
  1|2)
    ;;
  *)
    die "Unsupported --layout mode: $layout (expected 1 or 2)"
    ;;
esac

if [ -z "$work_dir" ]; then
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/photos2pdf.XXXXXX")
  work_dir_is_temp=1
fi

project_dir="$work_dir/project"
pages_dir="$work_dir/pages"
project_file="$project_dir/photos2pdf.ScanTailor"
inputs_manifest="$work_dir/input-files.txt"
pages_manifest="$work_dir/output-pages.txt"
override_dir="$work_dir/dewarp-off-override"
override_project_dir="$override_dir/project"
override_pages_dir="$override_dir/pages"
override_project_file="$override_project_dir/photos2pdf-dewarp-off.ScanTailor"
final_pages_dir="$work_dir/final-pages"

if [ -e "$output_pdf" ]; then
  if ((force)); then
    rm -f "$output_pdf"
  else
    die "Output PDF already exists: $output_pdf (use --force to overwrite)"
  fi
fi

if [ -e "$project_dir" ] || [ -e "$pages_dir" ] || [ -e "$inputs_manifest" ] || [ -e "$pages_manifest" ] || [ -e "$override_dir" ]; then
  if ((force)); then
    rm -rf "$project_dir" "$pages_dir"
    rm -rf "$override_dir"
    rm -rf "$final_pages_dir"
    rm -f "$inputs_manifest" "$pages_manifest"
  else
    die "Work products already exist in $work_dir (use --force to overwrite)"
  fi
fi

mkdir -p "$project_dir" "$pages_dir" "$(dirname "$output_pdf")"

mapfile -d '' images < <(
  find "$input_dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0 | LC_ALL=C sort -z
)

((${#images[@]} > 0)) || die "No JPG/JPEG files found in $input_dir"

printf '%s\n' "${images[@]}" > "$inputs_manifest"

st_args=(
  --layout="$layout"
  --dpi="$dpi"
  --output-dpi="$dpi"
  --deskew=auto
  --enable-page-detection
  --enable-fine-tuning
  --margins="$margin"
  --color-mode="$color_mode"
  --white-margins
  --dewarping="$dewarping"
  --depth-perception="$depth_perception"
  --output-project="$project_file"
)

if ((layout == 2)); then
  st_args+=(--layout-direction=lr)
fi

if ((normalize_illumination)); then
  st_args+=(--normalize-illumination)
fi

printf 'Input directory: %s\n' "$input_dir"
printf 'Output PDF: %s\n' "$output_pdf"
printf 'Work directory: %s\n' "$work_dir"
printf 'Source images: %s\n' "${#images[@]}"
printf 'Layout: %s\n' "$([ "$layout" -eq 1 ] && echo "1 page per image" || echo "2 pages per image (spread)")"
printf 'Running ScanTailor...\n'

scantailor-universal-cli "${st_args[@]}" "${images[@]}" "$pages_dir"

if ((${#dewarp_off_images[@]} > 0)); then
  override_image_paths=()
  for requested_name in "${dewarp_off_images[@]}"; do
    matched_path=
    for image_path in "${images[@]}"; do
      if [ "$(basename "$image_path")" = "$requested_name" ]; then
        matched_path=$image_path
        break
      fi
    done

    [ -n "$matched_path" ] || die "Could not find requested --dewarp-off-image in input set: $requested_name"
    override_image_paths+=("$matched_path")
  done

  printf 'Reprocessing with dewarping off: %s\n' "$(join_by ', ' "${dewarp_off_images[@]}")"

  mkdir -p "$override_project_dir" "$override_pages_dir"
  override_args=(
    --layout="$layout"
    --dpi="$dpi"
    --output-dpi="$dpi"
    --deskew=auto
    --enable-page-detection
    --enable-fine-tuning
    --margins="$margin"
    --color-mode="$color_mode"
    --white-margins
    --dewarping=off
    --depth-perception="$depth_perception"
    --output-project="$override_project_file"
  )

  if ((layout == 2)); then
    override_args+=(--layout-direction=lr)
  fi

  if ((normalize_illumination)); then
    override_args+=(--normalize-illumination)
  fi

  scantailor-universal-cli "${override_args[@]}" "${override_image_paths[@]}" "$override_pages_dir"

  for requested_name in "${dewarp_off_images[@]}"; do
    stem=${requested_name%.*}
    if ((layout == 1)); then
      rm -f "$pages_dir/${stem}.tif"
      mv "$override_pages_dir/${stem}.tif" "$pages_dir/"
    else
      rm -f "$pages_dir/${stem}_"*.tif
      mv "$override_pages_dir/${stem}_"*.tif "$pages_dir/"
    fi
  done
fi

mapfile -d '' page_files < <(
  find "$pages_dir" -maxdepth 1 -type f -iname '*.tif' -print0 | LC_ALL=C sort -z
)

((${#page_files[@]} > 0)) || die "ScanTailor produced no TIFF pages in $pages_dir"

if ((binarize)); then
  mkdir -p "$final_pages_dir"
  final_page_files=()
  for page_file in "${page_files[@]}"; do
    final_page_file="$final_pages_dir/$(basename "$page_file")"
    threshold_image_to_bilevel "$page_file" "$final_page_file" "$binarize_threshold_offset"
    final_page_files+=("$final_page_file")
  done
else
  final_page_files=("${page_files[@]}")
fi

printf '%s\n' "${page_files[@]}" > "$pages_manifest"

printf 'Assembling PDF from %s pages...\n' "${#final_page_files[@]}"
assemble_pdf "$output_pdf" "${final_page_files[@]}"

if ((cleanup)); then
  rm -rf "$work_dir"
fi

printf 'Done.\n'
printf 'PDF: %s\n' "$output_pdf"
if ((cleanup)); then
  printf 'Work directory removed.\n'
else
  printf 'Work directory: %s\n' "$work_dir"
  if ((work_dir_is_temp)); then
    printf 'Note: temporary work directory retained; use --cleanup to remove it automatically.\n'
  fi
fi
