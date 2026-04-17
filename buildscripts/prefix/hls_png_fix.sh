#!/bin/bash -e

# Apply FFmpeg patches for MPEG-TS disguised as PNG (HLS + generic mpegts probe).
# Usage:
#   hls_png_fix.sh [path-to-ffmpeg-source]
#
# Apply a unified diff patch file (no Python dependency).
# Build-time logs go to stderr with prefix [hls_png_fix].
# Runtime logs use both AV_LOG_VERBOSE and AV_LOG_WARNING for visibility.

log() {
	printf '[hls_png_fix] %s\n' "$1" >&2
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${1:-$(cd "$here/.." && pwd)/deps/ffmpeg}"
hls_c="$target_dir/libavformat/hls.c"
mpegts_c="$target_dir/libavformat/mpegts.c"

log "target_dir=$target_dir"

if [ ! -f "$hls_c" ]; then
	log "ERROR: hls.c not found at $hls_c"
	exit 1
fi
if [ ! -f "$mpegts_c" ]; then
	log "ERROR: mpegts.c not found at $mpegts_c"
	exit 1
fi

log "hls.c present ($(wc -c <"$hls_c" | tr -d ' ') bytes)"
log "mpegts.c present ($(wc -c <"$mpegts_c" | tr -d ' ') bytes)"

if grep -q "HLS_PNG_FIX_FORCE_MPEGTS" "$hls_c" && grep -q "MPEGTS_PROBE_SKIP_PNG" "$mpegts_c"; then
	log "markers already present, skip (idempotent)"
	exit 0
fi

if grep -q "ret = av_probe_input_buffer(&pls->pb.pub, &in_fmt, url, NULL, 0, 0)" "$hls_c"; then
	log "found av_probe_input_buffer(&pls->pb.pub...) line (inject anchor OK)"
else
	log "WARN: expected av_probe_input_buffer anchor string not found verbatim; patch may still match with regex"
fi

apply_one() {
	local patch_file="$1"
	if [ ! -f "$patch_file" ]; then
		log "ERROR: patch file not found at $patch_file"
		exit 1
	fi
	log "applying patch file ($(basename "$patch_file"))..."
	if ! (cd "$target_dir" && patch -p1 --forward --binary <"$patch_file"); then
		log "ERROR: patch command failed for $(basename "$patch_file")"
		exit 1
	fi
}

if ! command -v patch >/dev/null 2>&1; then
	log "ERROR: 'patch' command not found in PATH"
	exit 1
fi

# Patches are LF-based; some Windows checkouts use CRLF in the FFmpeg tree.
for f in libavformat/hls.c libavformat/mpegts.c; do
	if [ -f "$target_dir/$f" ]; then
		sed -i 's/\r$//' "$target_dir/$f" 2>/dev/null || true
	fi
done

apply_one "$here/hls_png_fix.patch"
apply_one "$here/mpegts_png_probe.patch"

if grep -q "HLS_PNG_FIX_FORCE_MPEGTS" "$hls_c" && grep -q "MPEGTS_PROBE_SKIP_PNG" "$mpegts_c"; then
	log "verified markers in hls.c and mpegts.c on disk"
	exit 0
fi

log "ERROR: marker missing after patch apply (unexpected)"
exit 1
