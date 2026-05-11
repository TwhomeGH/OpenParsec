#pragma once

#include <stdint.h>
#include <stdbool.h>

struct audio;

void audio_init(struct audio **ctx_out);
void audio_destroy(struct audio **ctx_out);
void audio_clear(struct audio **ctx_out);
void audio_cb(const int16_t *pcm, uint32_t frames, void *opaque);
void audio_mute(bool muted, const void *opaque);

// bridge for Swift to write logs from C
void write_log_from_swift(const char *msg);
void set_logging_enabled(bool enabled);
void set_audio_logging_enabled(bool enabled);


