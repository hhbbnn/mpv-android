#!/bin/bash -e

# Apply FFmpeg HLS workaround for TS segments disguised as PNG.
# Usage:
#   hls_png_fix.sh [path-to-ffmpeg-source]

target_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/deps/ffmpeg}"
target_file="$target_dir/libavformat/hls.c"

if [ ! -f "$target_file" ]; then
	echo "hls_png_fix: ffmpeg hls.c not found at: $target_file" >&2
	exit 1
fi

if grep -q "HLS_PNG_FIX_FORCE_MPEGTS" "$target_file"; then
	echo "hls_png_fix: already applied"
	exit 0
fi

python3 - "$target_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("\r\n", "\n")
orig = text

# Start: probe block first line (spacing may differ between checkouts / reformat).
start_m = re.search(
    r"^[ \t]*pls->ctx->probesize\s*=\s*s->probesize\s*>\s*0\s*\?\s*s->probesize\s*:\s*1024\s*\*\s*4\s*;",
    text,
    flags=re.M,
)
if not start_m:
    print("hls_png_fix: probe start marker not found", file=sys.stderr)
    sys.exit(1)
si = start_m.start()

# End: success-path av_free(url) then closing brace of else, blank line, seg = ...
end_m = re.search(
    r"(^[ \t]*av_free\(url\);\s*\n)"
    r"([ \t]*\}\s*\n)"
    r"(\s*\n)"
    r"([ \t]*seg\s*=\s*current_segment\(pls\)\s*;)",
    text[si:],
    flags=re.M,
)
if not end_m:
    print("hls_png_fix: probe end anchor not found", file=sys.stderr)
    sys.exit(1)
end = si + end_m.start(1) + len(end_m.group(1))

new_inner = """            /* HLS_PNG_FIX_FORCE_MPEGTS: force mpegts demuxer for TS disguised as PNG */
            void *iter = NULL;
            while ((in_fmt = av_demuxer_iterate(&iter)))
                if (strstr(in_fmt->name, "mpegts"))
                    break;
            if (!in_fmt)
                in_fmt = av_find_input_format("mpegts");
"""

text = text[:si] + new_inner + text[end:]

# Remove playlist-local char *url (not struct segment's member).
url_decl = re.compile(
    r"(^[ \t]*(?:const|ff_const59)\s+AVInputFormat\s*\*in_fmt\s*=\s*NULL;\s*\n)"
    r"[ \t]*char\s*\*\s*url;\s*\n",
    flags=re.M,
)
text, n = url_decl.subn(r"\1", text, count=1)
if n != 1:
    print("hls_png_fix: could not remove playlist char *url declaration", file=sys.stderr)
    sys.exit(1)

if text == orig:
    print("hls_png_fix: no changes made", file=sys.stderr)
    sys.exit(1)

if "HLS_PNG_FIX_FORCE_MPEGTS" not in text:
    print("hls_png_fix: verification failed", file=sys.stderr)
    sys.exit(1)

path.write_text(text, encoding="utf-8")
print("hls_png_fix: patch applied")
PY

if grep -q "HLS_PNG_FIX_FORCE_MPEGTS" "$target_file"; then
	exit 0
fi

echo "hls_png_fix: patch failed verification" >&2
exit 1
