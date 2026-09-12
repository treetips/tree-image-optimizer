# 画像圧縮

## ✳️ JPEG

### ✏️ コマンド

```shell
jpegoptim \
  -m${QUALITY} \
  -o -d "$outputDir" \
  "$output"
```

拡張子は固定で `.jpg` とします。
`最適化種別` 毎のパラメータは以下で固定します。

| 最適化種別    | QUALITY |
|----------|---------|
| アニメ・イラスト | 75      |
| 実写・写真.   | 80      |
| 速度優先     | 60      |
| 画質最優先    | 95      |

### ✏️ help

```shell
❯ jpegoptim --help
jpegoptim v1.5.6  Copyright (C) 1996-2025, Timo Kokkonen
Usage: jpegoptim [options] <filenames>

  -d<path>, --dest=<path>
                    specify alternative destination directory for
                    optimized files (default is to overwrite originals)
  -f, --force       force optimization
  -h, --help        display this help and exit
  -m<quality>, --max=<quality>
                    set maximum image quality factor (disables lossless
                    optimization mode, which is by default on)
                    Valid quality values: 0 - 100
  -n, --noaction    don't really optimize files, just print results
  -S<size>, --size=<size>
                    Try to optimize file to given size (disables lossless
                    optimization mode). Target size is specified either in
                    kilo bytes (1 - n) or as percentage (1% - 99%)
  -T<threshold>, --threshold=<threshold>
                    keep old file if the gain is below a threshold (%)
  -w<max>, --workers=<max>
                    set maximum number of parallel threads (default is 1)
  -b, --csv         print progress info in CSV format
  -o, --overwrite   overwrite target file even if it exists (meaningful
                    only when used with -d, --dest option)
  -p, --preserve    preserve file timestamps
  -P, --preserve-perms
                    preserve original file permissions by overwriting it
  -q, --quiet       quiet mode
  -r, --retry       try (recursively) optimize until file size does not change anymore
  -t, --totals      print totals after processing all files
  -v, --verbose     enable verbose mode (positively chatty)
  -V, --version     print program version

  -s, --strip-all   strip all markers from output file
  --strip-none      do not strip any markers
  --strip-adobe     strip Adobe (APP14) markers from output file
  --strip-com       strip Comment markers from output file
  --strip-exif      strip Exif markers from output file
  --strip-iptc      strip IPTC/Photoshop (APP13) markers from output file
  --strip-icc       strip ICC profile markers from output file
  --strip-jfif      strip JFIF markers from output file
  --strip-jfxx      strip JFXX (JFIF Extension) markers from output file
  --strip-xmp       strip XMP markers markers from output file

  --keep-all        do not strip any markers (same as --strip-none)
  --keep-adobe      preserve any Adobe (APP14) markers
  --keep-com        preserve any Comment markers
  --keep-exif       preserve any Exif markers
  --keep-iptc       preserve any IPTC/Photoshop (APP13) markers
  --keep-icc        preserve any ICC profile markers
  --keep-jfif       preserve any JFIF markers
  --keep-jfxx       preserve any JFXX (JFIF Extension) markers
  --keep-xmp        preserve any XMP markers markers

  --all-normal      force all output files to be non-progressive
  --all-progressive force all output files to be progressive
  --auto-mode       select normal or progressive based on which produces
                    smaller output file
  --stdout          send output to standard output (instead of a file)
  --stdin           read input from standard input (instead of a file)
  --files-stdin     Read names of files to process from stdin
  --files-from=FILE Read names of files to process from a file
  --nofix           skip processing of input files if they contain any errors
  --save-extra      preserve extraneous data after the end of image
```

## ✳️ PNG

### ✏️ コマンド

```shell
pngoptim \
  "$output" \
  -o "$output" \
  --quality ${QUALITY}
```

拡張子は固定で `.jpg` とします。
`最適化種別` 毎のパラメータは以下で固定します。

| 最適化種別    | QUALITY |
|----------|---------|
| アニメ・イラスト | 75      |
| 実写・写真.   | 80      |
| 速度優先     | 60      |
| 画質最優先    | 95      |

### ✏️ help

```shell
❯ pngoptim --help
Fast PNG quantization CLI — lossy PNG compression like pngquant

Usage: pngoptim [OPTIONS] <INPUT>...

Arguments:
  <INPUT>...


Options:
  -o, --output <FILE>


      --ext <SUFFIX>
          [default: -mvp.png]

      --quality <N | -N | N- | MIN-MAX>


      --speed <SPEED>
          [default: 4]

      --floyd[=<N>]


      --nofs


      --strip


      --posterize <POSTERIZE>


      --force


      --skip-if-larger


  -q, --quiet


      --no-icc


      --apng-mode <APNG_MODE>
          Possible values:
          - safe:       Only fold duplicate frames (safe, no visual risk)
          - aggressive: Also minimize frame rectangles (may alter dispose/blend semantics)

          [default: safe]

  -h, --help
          Print help (see a summary with '-h')

  -V, --version
          Print version
```

## ✳️ JPEG XL

### ✏️ コマンド

```shell
cjxl \
  "$real_input" \
  "$output" \
  --distance "${JXL_DISTANCE}" \
  -e "${JXL_EFFORT}" \
  --num_threads=${CJXL_THREADS} \
  ${EXTRA_OPTS}
```

拡張子は固定で `.jxl` とします。
`最適化種別` 毎のパラメータは以下で固定します。

| 最適化種別    | JXL_DISTANCE | JXL_EFFORT | EXTRA_OPTS        |
|----------|--------------|------------|-------------------|
| アニメ・イラスト | 0.8          | 7          | --lossless_jpeg=0 |
| 実写・写真.   | 1.0          | 7          | --lossless_jpeg=0 |
| 速度優先     | 1.2          | 7          | --lossless_jpeg=0 |
| 画質最優先    | 0.5          | 80         | --lossless_jpeg=0 |

### ✏️ help

```shell
❯ cjxl --help
JPEG XL encoder v0.12.0 0.12.0 [_NEON_BF16_,NEON] {AppleClang 21.0.0.21000099}
Usage: cjxl INPUT OUTPUT [OPTIONS...]
 INPUT
    the input can be JXL, PPM, PNM, PFM, PAM, PGX, PNG, APNG, GIF, JPEG, EXR
 OUTPUT
    the compressed JXL output file

Basic options:
 -d DISTANCE, --distance=DISTANCE
    Target visual distance in JND units, range: 0.0 .. 25.0.
    0.0 = mathematically lossless, default for JPEG/GIF input.
    1.0 = visually lossless, default for other input.
    Recommended range: 0.5 .. 3.0. Higher values allow more distortion.
Mutually exclusive with --quality.
 -q QUALITY, --quality=QUALITY
    Internally mapped to --distance, range: 0 .. 100.
    100 = mathematically lossless. 90 = visually lossless.
    Quality values roughly match libjpeg quality.
    Recommended range: 68 .. 96. Mutually exclusive with --distance.
 -e EFFORT, --effort=EFFORT
    Encoder effort, range: 1 .. 10, default = 7.
    Higher values allow more computation, generally achieving smaller output at same quality.
    For lossy encoding, higher effort should achieve more accurate quality.
 -V, --version
    Print encoder library version number and exit.
 --quiet
    Minimal printing.
 -v, --verbose
    Verbose printing; can be repeated and also applies to help (!).
 --buffering=-1..3
    Controls how much input buffering libjxl uses, affecting memory usage and compression quality.
    -1 = encoder chooses (default). 0 = buffer entire image (most memory, best compression).
    1 = stream input for large images. 2 = stream input with a lower threshold.
    3 = deprecated; use --output_mode to control output streaming.

 -h, --help
    Prints this help message. Add -v (up to a total of 4 times) to see more options.
```

## ✳️ AV1

### ✏️ コマンド

```shell
avifenc \
  --speed "${AVIF_SPEED}" \
  -q "${AVIF_QUALITY}" \
  -y "${AVIF_YUV}" \
  "${AOM_OPTS[@]}" \
  "$input" \
  "$output"
```

拡張子は固定で `.avif` とします。
`最適化種別` 毎のパラメータは以下で固定します。

| 最適化種別    | AVIF_SPEED | AVIF_QUALITY | AVIF_YUV | AOM_OPTS                                |
|----------|------------|--------------|----------|-----------------------------------------|
| アニメ・イラスト | 3          | 90           | 444      | ("-a" "end-usage=q" "-a" "cq-level=20") |
| 実写・写真    | 4          | 85           | 420      | ("-a" "end-usage=q" "-a" "cq-level=22") |
| 速度優先     | 8          | 70           | 420      |                                         |
| 画質最優先    | 4          | 90           | 444      | ("-a" "end-usage=q" "-a" "cq-level=16") |

### ✏️ help

```shell
❯ avifenc --help
Syntax: avifenc [options] input.[jpg|jpeg|png|y4m] output.avif
Standard options:
    -h,--help                         : Show syntax help (this page)
    -V,--version                      : Show the version number

Basic options:
    -q,--qcolor Q                     : Quality for color in 0..100 where 100 is lossless
    --qalpha Q                        : Quality for alpha in 0..100 where 100 is lossless
    -s,--speed S                      : Encoder speed in 0..10 where 0 is the slowest, 10 is the fastest. Or 'default' or 'd' for codec internal defaults. (Default: 6)

Advanced options:
    -j,--jobs J                       : Number of jobs (worker threads), or 'all' to potentially use as many cores as possible. (Default: all)
    --no-overwrite                    : Never overwrite existing output file
    -o,--output FILENAME              : Instead of using the last filename given as output, use this filename
    -l,--lossless                     : Set all defaults to encode losslessly, and emit warnings when settings/input don't allow for it
    -d,--depth D[,Dextension]         : D is the output bit depth per channel. D must be 8, 10 or 12. (JPEG/PNG only; y4m: D must match the input bit depth, and Dextension is unsupported)
                                        If specified, Dextension adds a hidden encoded image of Dextension bit depth in the same file as the primary image to reach 16-bit depth at decoding.
                                        See avifSampleTransformRecipe for the supported combinations (8,8 and 12,4 and 12,8).
    -y,--yuv FORMAT                   : Output format, one of 'auto' (default), 444, 422, 420 or 400. Ignored for y4m (y4m format is retained)
                                        For JPEG, auto honors the JPEG's internal format, if possible. For grayscale PNG, auto defaults to 400. For all other cases, auto defaults to 444
    -p,--premultiply                  : Premultiply color by the alpha channel and signal this in the AVIF
    --sharpyuv                        : Use sharp RGB to YUV420 conversion (if supported). Ignored for y4m or if output is not 420.
    --stdin                           : Read input from stdin instead of file paths. No other input is allowed. The input format isassumed to be y4m unless --input-format is specified. The output file path must still be provided.
    --input-format FORMAT             : File format of the input data. One of: jpeg/png/y4m/auto. (Default: auto, except for stdin where auto is not supported and the default is y4m)
    --cicp,--nclx P/T/M               : Set CICP values (nclx colr box) (3 raw numbers, use -r to set range flag)
                                        P = color primaries
                                        T = transfer characteristics
                                        M = matrix coefficients
                                        Use 2 for any you wish to leave unspecified
    -r,--range RANGE                  : YUV range, one of 'limited' or 'l', 'full' or 'f'. (JPEG/PNG only, default: full; For y4m, range is retained)
    --target-size S                   : Set target file size in bytes (up to 7 times slower)
    --progressive                     : Automatically set parameters to encode a simple layered image supporting progressive rendering from a single input frame.
    --layered                         : Encode a layered AVIF. Each input is encoded as one layer and at most 4 layers can be encoded.
    -g,--grid MxN                     : Encode a single-image grid AVIF with M cols & N rows. Either supply MxN identical W/H/D images, or a single
                                        image that can be evenly split into the MxN grid and follow AVIF grid image restrictions. The grid will adopt
                                        the color profile of the first image supplied.
    -c,--codec C                      : Codec to use (choose from versions list below)
    --exif FILENAME                   : Provide an Exif metadata payload to be associated with the primary item (implies --ignore-exif)
    --xmp FILENAME                    : Provide an XMP metadata payload to be associated with the primary item (implies --ignore-xmp)
    --icc FILENAME                    : Provide an ICC profile payload to be associated with the primary item (implies --ignore-icc)
    --timescale,--fps V               : Timescale for image sequences. If all frames are 1 timescale in length, this is equivalent to frames per second. (Default: 30)
                                        If neither duration nor timescale are set, avifenc will attempt to use the framerate storedin a y4m header, if present.
    --creation-time                   : Creation time for image sequences, in seconds since 1970-01-01 00:00:00 UTC (the Unix epoch). (Default: 0, use the modification time)
    --modification-time               : Modification time for image sequences, in seconds since 1970-01-01 00:00:00 UTC (the Unix epoch). (Default: 0, use the current time)
    -k,--keyframe INTERVAL            : Maximum keyframe interval for image sequences (any set of INTERVAL consecutive frames will have at least one keyframe). Set to 0 to disable (default).
    --ignore-exif                     : If the input file contains embedded Exif metadata, ignore it (no-op if absent)
    --ignore-xmp                      : If the input file contains embedded XMP metadata, ignore it (no-op if absent)
    --ignore-profile,--ignore-icc     : If the input file contains an embedded color profile, ignore it (no-op if absent)
    --pasp H,V                        : Add pasp property (aspect ratio). H=horizontal spacing, V=vertical spacing
    --crop CROPX,CROPY,CROPW,CROPH    : Add clap property (clean aperture), but calculated from a crop rectangle
    --clap WN,WD,HN,HD,HON,HOD,VON,VOD: Add clap property (clean aperture). Width, Height, HOffset, VOffset (in numerator/denominator pairs)
    --irot ANGLE                      : Add irot property (rotation), in 0..3. Makes (90 * ANGLE) degree rotation anti-clockwise
    --imir AXIS                       : Add imir property (mirroring). 0=top-to-bottom, 1=left-to-right
    --clli MaxCLL,MaxPALL             : Add clli property (content light level information).
    --repetition-count N              : Number of times an animated image sequence will be repeated, or 'infinite' for infinite repetitions. (Default: infinite)
    --                                : Signal the end of options. Everything after this is interpreted as file names.

Updatable options:
  The following options can optionally have a :u (or :update) suffix like `-q:u Q`, to apply only to input files appearing after the option:
    -q,--qcolor Q                     : Quality for color in 0..100 where 100 is lossless
    --qalpha Q                        : Quality for alpha in 0..100 where 100 is lossless
    --tilerowslog2 R                  : log2 of number of tile rows in 0..6. (Default: 0)
                                        If specified, switch to manual tiling.
    --tilecolslog2 C                  : log2 of number of tile columns 0..6. (Default: 0)
                                        If specified, switch to manual tiling.
    --autotiling                      : Set --tilerowslog2 and --tilecolslog2 automatically
                                        If specified, switch to automatic tiling.
                                        avifenc starts in automatic tiling mode.
    --min QP                          : Deprecated, use -q 0..100 instead
    --max QP                          : Deprecated, use -q 0..100 instead
    --minalpha QP                     : Deprecated, use --qalpha 0..100 instead
    --maxalpha QP                     : Deprecated, use --qalpha 0..100 instead
    --scaling-mode N[/D]              : Set frame (layer) scaling mode as given fraction. If omitted, the denominator defaults to 1. (Default: 1/1)
    --duration D                      : Frame durations (in timescales) (default: 1). This option always applies to following inputs with or without the `:u` suffix.
    -a,--advanced KEY[=VALUE]         : Pass an advanced, codec-specific key/value string pair directly to the codec. avifenc will warn on any not used by the codec.

aom-specific advanced options:
    1. <key>=<value> applies to both the color (YUV) planes and the alpha plane (if present).
    2. color:<key>=<value> or c:<key>=<value> applies only to the color (YUV) planes.
    3. alpha:<key>=<value> or a:<key>=<value> applies only to the alpha plane (if present).
       Since the alpha plane is encoded as a monochrome image, the options that refer to the chroma planes,
       such as enable-chroma-deltaq=B, should not be used with the alpha plane. In addition, the film grain
       options are unlikely to make sense for the alpha plane.

    When used with libaom 3.0.0 or later, any key-value pairs supported by the aom_codec_set_option() function
    can be used. When used with libaom 2.0.x or older, the following key-value pairs can be used:

    aq-mode=M                         : Adaptive quantization mode. 0=off (default), 1=variance, 2=complexity, 3=cyclic refresh
    cq-level=Q                        : Constant/Constrained Quality level in 0..63, end-usage must be set to cq or q
    enable-chroma-deltaq=B            : Enable delta quantization in chroma planes. 0=disable (default), 1=enable
    end-usage=MODE                    : Rate control mode, one of 'vbr', 'cbr', 'cq', or 'q'
    sharpness=S                       : Bias towards block sharpness in rate-distortion optimization of transform coefficients in 0..7. (Default: 0)
    tune=METRIC                       : Tune the encoder for distortion metric, one of 'psnr', 'ssim' or 'iq'.
                                        (Default for color: still non-RGB images (libaom v3.13.0+): iq, otherwise: ssim; default for alpha: psnr)
    film-grain-test=TEST              : Film grain test vectors in 0..16. 0=none (default), 1=test1, 2=test2, ... 16=test16
    film-grain-table=FILENAME         : Path to file containing film grain parameters

Version: 1.4.2 (dav1d [dec]:1.5.4, aom [enc/dec]:3.14.1)
libyuv : unavailable
```

## ✳️ WebP

### ✏️ コマンド

```shell
cwebp \
  -preset "${WEBP_PRESET}" \
  -q "${QUALITY}" \
  -m "${WEBP_METHOD}" \
  -mt \
  "$input" \
  -o "$output"
```

拡張子は固定で `.webp` とします。
`最適化種別` 毎のパラメータは以下で固定します。

| 最適化種別    | WEBP_PRESET | WEBP_METHOD (`-m` 0=fast..6=slowest) | 補足                                                               |
|----------|-------------|--------------------------------------|------------------------------------------------------------------|
| アニメ・イラスト | drawing     | 4                                    | エッジ・ベタ塗り保持に強い `drawing`。デフォルトの `-m 4` で品質と速度のバランス                |
| 実写・写真    | photo       | 4                                    | 実写向けチューニングの `photo`。`-m 4`（デフォルト）でバランス重視                         |
| 速度優先     | default     | 0                                    | プリセット補正なしの `default` + `-m 0`（最速）でエンコード時間最優先。`-sns`/`-f` 等はデフォルト |
| 画質最優先    | photo       | 6                                    | 実写/イラスト両用で高圧縮な `photo` + `-m 6`（最遅・最高圧縮効率）。速度を犠牲にサイズと歪みを最優先      |

> 参考: `-m` は圧縮効率（探索量）であり、`0` が最速・低圧縮、`6` が最遅・高圧縮。`-preset` は `drawing` / `photo` / `default` などが内部の `-sns` / `-f` / `-sharpness` / セグメント等のデフォルトを上書きするため、`-preset` を先頭に置いた上で `-m` を上書きする運用とします。

### ✏️ help

```shell
❯ cwebp --help                                          

Usage:
 cwebp [-preset <...>] [options] in_file [-o out_file]

If input size (-s) for an image is not specified, it is
assumed to be a PNG, JPEG, TIFF or WebP file.
Note: Animated PNG and WebP files are not supported.

Options:
  -h / -help ............. short help
  -H / -longhelp ......... long help
  -q <float> ............. quality factor (0:small..100:big), default=75
  -alpha_q <int> ......... transparency-compression quality (0..100),
                           default=100
  -preset <string> ....... preset setting, one of:
                            default, photo, picture,
                            drawing, icon, text
     -preset must come first, as it overwrites other parameters
  -z <int> ............... activates lossless preset with given
                           level in [0:fast, ..., 9:slowest]

  -m <int> ............... compression method (0=fast, 6=slowest), default=4
  -segments <int> ........ number of segments to use (1..4), default=4
  -size <int> ............ target size (in bytes)
  -psnr <float> .......... target PSNR (in dB. typically: 42)

  -s <int> <int> ......... input size (width x height) for YUV
  -sns <int> ............. spatial noise shaping (0:off, 100:max), default=50
  -f <int> ............... filter strength (0=off..100), default=60
  -sharpness <int> ....... filter sharpness (0:most .. 7:least sharp), default=0
  -strong ................ use strong filter instead of simple (default)
  -nostrong .............. use simple filter instead of strong
  -sharp_yuv ............. use sharper (and slower) RGB->YUV conversion
  -partition_limit <int> . limit quality to fit the 512k limit on
                           the first partition (0=no degradation ... 100=full)
  -pass <int> ............ analysis pass number (1..10)
  -qrange <min> <max> .... specifies the permissible quality range
                           (default: 0 100)
  -crop <x> <y> <w> <h> .. crop picture with the given rectangle
  -resize <w> <h> ........ resize picture (*after* any cropping)
  -resize_mode <string> .. one of: up_only, down_only, always (default)
  -mt .................... use multi-threading if available
  -low_memory ............ reduce memory usage (slower encoding)
  -map <int> ............. print map of extra info
  -print_psnr ............ prints averaged PSNR distortion
  -print_ssim ............ prints averaged SSIM distortion
  -print_lsim ............ prints local-similarity distortion
  -d <file.pgm> .......... dump the compressed output (PGM file)
  -alpha_method <int> .... transparency-compression method (0..1), default=1
  -alpha_filter <string> . predictive filtering for alpha plane,
                           one of: none, fast (default) or best
  -exact ................. preserve RGB values in transparent area, default=off
  -blend_alpha <hex> ..... blend colors against background color
                           expressed as RGB values written in
                           hexadecimal, e.g. 0xc0e0d0 for red=0xc0
                           green=0xe0 and blue=0xd0
  -noalpha ............... discard any transparency information
  -lossless .............. encode image losslessly, default=off
  -near_lossless <int> ... use near-lossless image preprocessing
                           (0..100=off), default=100
  -hint <string> ......... specify image characteristics hint,
                           one of: photo, picture or graph

  -metadata <string> ..... comma separated list of metadata to
                           copy from the input to the output if present.
                           Valid values: all, none (default), exif, icc, xmp

  -short ................. condense printed message
  -quiet ................. don't print anything
  -version ............... print version number and exit
  -noasm ................. disable all assembly optimizations
  -v ..................... verbose, e.g. print encoding/decoding times
  -progress .............. report encoding progress

Experimental Options:
  -jpeg_like ............. roughly match expected JPEG size
  -af .................... auto-adjust filter strength
  -pre <int> ............. pre-processing filter

Supported input formats:
  WebP, JPEG, PNG, PNM (PGM, PPM, PAM), TIFF
```