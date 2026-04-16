#!/bin/bash -e

# Apply FFmpeg HLS workaround for TS segments disguised as PNG.
# Usage:
#   hls_png_fix.sh [path-to-ffmpeg-source]
#
# Python logic lives in hls_png_fix.py so CRLF in this shell script cannot break a heredoc.
# Build-time logs go to stderr with prefix [hls_png_fix].
# Runtime logs use both AV_LOG_VERBOSE and AV_LOG_WARNING for visibility.

log() {
	printf '[hls_png_fix] %s\n' "$1" >&2
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${1:-$(cd "$here/.." && pwd)/deps/ffmpeg}"
target_file="$target_dir/libavformat/hls.c"

log "target_dir=$target_dir"

if [ ! -f "$target_file" ]; then
	log "ERROR: hls.c not found at $target_file"
	exit 1
fi

log "hls.c present ($(wc -c <"$target_file" | tr -d ' ') bytes)"

if grep -q "HLS_PNG_FIX_FORCE_MPEGTS" "$target_file"; then
	log "marker already present, skip (idempotent)"
	exit 0
fi

if grep -q "ret = av_probe_input_buffer(&pls->pb.pub, &in_fmt, url, NULL, 0, 0)" "$target_file"; then
	log "found av_probe_input_buffer(&pls->pb.pub...) line (inject anchor OK)"
else
	log "WARN: expected av_probe_input_buffer anchor string not found verbatim; patch may still match with regex"
fi

# Pick a real Python 3. Skip Windows "python3" under WindowsApps (often a store stub that exits 49).
pick_python() {
	local c path
	for c in python3 python; do
		path="$(command -v "$c" 2>/dev/null)" || continue
		case "$path" in
			*[/\\]WindowsApps[/\\]* | *[/\\]windowsapps[/\\]*) continue ;;
		esac
		if ! "$c" -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 6) else 1)" >/dev/null 2>&1; then
			continue
		fi
		printf '%s\n' "$c"
		return 0
	done
	return 1
}

if ! PY="$(pick_python)"; then
	log "ERROR: no usable Python 3.6+ found (python3/python); avoid WindowsApps python stubs"
	exit 1
fi

log "running python rewrite ($PY)..."

export HLS_PNG_FIX_TARGET_FILE="$target_file"
"$PY" "$here/hls_png_fix.py"
py_status=$?
unset HLS_PNG_FIX_TARGET_FILE

log "python finished exit=$py_status"

if [ "$py_status" -ne 0 ]; then
	log "ERROR: python patch failed (exit $py_status)"
	exit 1
fi

if grep -q "HLS_PNG_FIX_FORCE_MPEGTS" "$target_file"; then
	log "verified marker in file on disk"
	exit 0
fi

log "ERROR: marker missing after python (unexpected)"
exit 1
