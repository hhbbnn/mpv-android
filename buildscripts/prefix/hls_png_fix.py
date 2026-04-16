#!/usr/bin/env python3
"""Rewrite FFmpeg libavformat/hls.c to force mpegts after probe (HLS PNG workaround)."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


def log(msg: str) -> None:
    print(f"[hls_png_fix] {msg}", file=sys.stderr)


def main() -> int:
    try:
        target = os.environ["HLS_PNG_FIX_TARGET_FILE"]
    except KeyError:
        log("ERROR: HLS_PNG_FIX_TARGET_FILE is not set")
        return 1

    path = Path(target)
    text = path.read_text(encoding="utf-8")
    text = text.replace("\r\n", "\n")
    orig = text
    log(f"read {path} ({len(text)} chars)")

    inject_after_probe = re.compile(
        r"(^[ \t]*ret\s*=\s*av_probe_input_buffer\(&pls->pb\.pub,\s*&in_fmt,\s*url,\s*NULL,\s*0,\s*0\);\s*\n)",
        flags=re.M,
    )

    m = inject_after_probe.search(text)
    if m:
        snippet = m.group(1).replace("\n", "\\n")
        log(f"regex matched probe line at offset {m.start()}: {snippet[:120]}...")
    else:
        log("ERROR: regex did not match av_probe_input_buffer line")

    injected_block = (
        "            /* HLS_PNG_FIX_FORCE_MPEGTS: force mpegts demuxer for TS disguised as PNG */\n"
        "            av_log(s, AV_LOG_WARNING, \"HLS_PNG_FIX_HIT: forcing mpegts after probe ret=%d\\n\", ret);\n"
        "            av_log(s, AV_LOG_VERBOSE, \"HLS_PNG_FIX: after av_probe_input_buffer ret=%d, "
        "forcing mpegts demuxer (no PNG header stripping)\\n\", ret);\n"
        "            if (ret < 0)\n"
        "                ret = 0;\n"
        "            void *iter = NULL;\n"
        "            while ((in_fmt = av_demuxer_iterate(&iter)))\n"
        "                if (strstr(in_fmt->name, \"mpegts\"))\n"
        "                    break;\n"
        "            if (!in_fmt)\n"
        "                in_fmt = av_find_input_format(\"mpegts\");\n"
        "            av_log(s, AV_LOG_WARNING, \"HLS_PNG_FIX_HIT: selected sub-demuxer '%s'\\n\",\n"
        "                 in_fmt && in_fmt->name ? in_fmt->name : \"(null)\");\n"
        "            av_log(s, AV_LOG_VERBOSE, \"HLS_PNG_FIX: selected sub-demuxer '%s'\\n\",\n"
        "                 in_fmt && in_fmt->name ? in_fmt->name : \"(null)\");\n"
    )

    text, n = inject_after_probe.subn(r"\1" + injected_block, text, count=1)
    if n != 1:
        log("ERROR: probe line not found or multiple ambiguous matches")
        return 1

    log(f"substitution count={n}, bytes delta={len(text) - len(orig)}")

    if text == orig:
        log("ERROR: no changes made after substitution")
        return 1

    if "HLS_PNG_FIX_FORCE_MPEGTS" not in text:
        log("ERROR: marker missing after patch")
        return 1

    path.write_text(text, encoding="utf-8")
    log("wrote patched hls.c OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
