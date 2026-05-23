Photos2pdf
==========

`photos2pdf` converts a directory of photographed open-book spreads into a cleaned PDF that is easier to feed into OCR or OMR tools.

It is designed around a specific workflow:

- each source image is a landscape photo of an open two-page spread
- files are processed in filename order
- each spread is split into left and right pages
- ScanTailor handles page detection, deskewing, margins, and optional dewarping
- the final pages can be binarized to strict black and white before PDF assembly

This is useful when a phone or camera gives you better raw capture than a flatbed scanner, but you still want a cleaner final document.

Requirements
------------

The script is a Bash wrapper around existing command-line tools. You need:

- `bash`
- `scantailor-universal-cli`
- ImageMagick tools, including `identify` and `convert`
- a `~/.local/bin` directory on your `PATH` if you want to use the provided installer

Notes:

- `scantailor-universal-cli` does the page splitting and cleanup work.
- The current script calls `identify` and `convert` directly for thresholding and PDF assembly. On systems that only expose ImageMagick through `magick`, you may need compatibility symlinks or package variants that still provide those commands.

Installation
------------

Clone the repo, then run the installer:

```bash
git clone /path/to/photos2pdf.git
cd photos2pdf
./install.sh
```

`./install.sh` does not copy files anywhere permanent except for a symlink:

- it makes sure `photos2pdf.sh` is executable
- it creates or updates `~/.local/bin/photos2pdf` as a symlink to `photos2pdf.sh`

If `~/.local/bin` is not on your `PATH`, the installer will tell you. Open a new shell or add it manually before using `photos2pdf`.

To remove the installed command later:

```bash
rm -f ~/.local/bin/photos2pdf
```

Usage
-----

```bash
photos2pdf [options] [INPUT_DIR] [OUTPUT_PDF]
```

If `INPUT_DIR` is omitted, the current directory is used. If `OUTPUT_PDF` is omitted, the output defaults to:

```text
INPUT_DIR/$(basename INPUT_DIR).pdf
```

Examples
--------

Use the current directory:

```bash
photos2pdf
```

Process a specific folder and let the script name the PDF:

```bash
photos2pdf "/path/to/book-photos"
```

Choose an explicit output file:

```bash
photos2pdf "/path/to/book-photos" "/path/to/output/book.pdf"
```

Disable dewarping for a few known-bad spreads:

```bash
photos2pdf \
  --dewarp-off-image IMG_0720.JPG \
  --dewarp-off-image IMG_0723.JPG \
  "/path/to/book-photos"
```

Keep all intermediate files in a predictable place for inspection:

```bash
photos2pdf \
  --work-dir /tmp/photos2pdf-debug \
  --force \
  "/path/to/book-photos"
```

Remove the working directory automatically after a successful run:

```bash
photos2pdf --cleanup "/path/to/book-photos"
```

Important Options
-----------------

- `--dpi N`
  Sets both ScanTailor input and output DPI. Default: `300`
- `--margin N`
  Preserves a white border around each page. Default: `30`
- `--dewarping auto|off`
  Controls ScanTailor dewarping. Default: `auto`
- `--dewarp-off-image NAME`
  Reprocesses one named source image with dewarping disabled after the main pass
- `--depth-perception N`
  ScanTailor dewarping depth. Default: `2.0`
- `--color-mode MODE`
  Passed through to ScanTailor. Default: `color_grayscale`
- `--no-normalize-illumination`
  Disables ScanTailor illumination normalization
- `--no-binarize`
  Skips final black-and-white conversion
- `--binarize-threshold-offset N`
  Adjusts the per-page mean threshold used during binarization
- `--work-dir DIR`
  Stores the ScanTailor project, TIFF pages, and manifests in a chosen directory
- `--cleanup`
  Removes the work directory after success
- `--force`
  Overwrites an existing output PDF and clears prior generated work products

Run `photos2pdf --help` for the full option list.

How It Works
------------

At a high level, the script does this:

1. Collect top-level `*.jpg` and `*.jpeg` files from the input directory.
2. Sort them by filename.
3. Run `scantailor-universal-cli` in two-page spread mode.
4. Split each spread into left and right pages.
5. Deskew, detect page bounds, and apply margins.
6. Optionally normalize illumination and dewarp pages.
7. Optionally re-run selected source images with `--dewarping=off`.
8. Optionally binarize each TIFF page using a threshold based on that page's mean brightness.
9. Assemble the final pages into a PDF.

By default the script keeps its working directory so you can inspect intermediate TIFF pages and the generated ScanTailor project. If you do not want that, use `--cleanup`.

Assumptions and Limitations
---------------------------

- Input images must be top-level `.jpg` or `.jpeg` files. The script does not recurse into subdirectories.
- Each input image is assumed to be a left/right two-page spread.
- Processing order is based on filename sorting, so your filenames need to reflect page order.
- `--dewarp-off-image` values must match the source image basenames exactly.
- The default output is meant to be cleaner than raw photos, not archival-perfect reproduction.
