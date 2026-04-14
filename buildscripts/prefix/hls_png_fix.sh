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

(
	cd "$target_dir"
	patch -p1 --forward --batch <<'EOF'
diff --git a/libavformat/hls.c b/libavformat/hls.c
--- a/libavformat/hls.c
+++ b/libavformat/hls.c
@@ -1953,7 +1953,6 @@ static int hls_read_header(AVFormatContext *s)
      /* Open the demuxer for each playlist */
      for (i = 0; i < c->n_playlists; i++) {
          struct playlist *pls = c->playlists[i];
-        char *url;
          const AVInputFormat *in_fmt = NULL;
 
          if (!(pls->ctx = avformat_alloc_context())) {
@@ -1989,23 +1988,14 @@ static int hls_read_header(AVFormatContext *s)
          }
          ffio_init_context(&pls->pb, pls->read_buffer, INITIAL_BUFFER_SIZE, 0, pls,
                            read_data, NULL, NULL);
-        pls->ctx->probesize = s->probesize > 0 ? s->probesize : 1024 * 4;
-        pls->ctx->max_analyze_duration = s->max_analyze_duration > 0 ? s->max_analyze_duration : 4 * AV_TIME_BASE;
-        pls->ctx->interrupt_callback = s->interrupt_callback;
-        url = av_strdup(pls->segments[0]->url);
-        ret = av_probe_input_buffer(&pls->pb, &in_fmt, url, NULL, 0, 0);
-        if (ret < 0) {
-            /* Free the ctx - it isn't initialized properly at this point,
-             * so avformat_close_input shouldn't be called. If
-             * avformat_open_input fails below, it frees and zeros the
-             * context, so it doesn't need any special treatment like this. */
-            av_log(s, AV_LOG_ERROR, "Error when loading first segment '%s'\n", url);
-            avformat_free_context(pls->ctx);
-            pls->ctx = NULL;
-            av_free(url);
-            goto fail;
-        }
-        av_free(url);
+        /* HLS_PNG_FIX_FORCE_MPEGTS:
+         * Some HLS providers prepend a fake PNG header before TS payload.
+         * For these non-standard streams, probing picks image2/png and fails.
+         * Force MPEG-TS demuxer here as a compatibility workaround.
+         */
+        void *iter = NULL;
+        while ((in_fmt = av_demuxer_iterate(&iter)))
+            if (strstr(in_fmt->name, "mpegts"))
+                break;
          pls->ctx->pb       = &pls->pb;
          pls->ctx->io_open  = nested_io_open;
          pls->ctx->flags   |= s->flags & ~AVFMT_FLAG_CUSTOM_IO;
EOF
)

if grep -q "HLS_PNG_FIX_FORCE_MPEGTS" "$target_file"; then
	echo "hls_png_fix: patch applied"
	exit 0
fi

echo "hls_png_fix: patch failed to apply cleanly" >&2
exit 1
