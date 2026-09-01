#pragma once
#include <stdint.h>

#include "opus.h"

typedef struct OggOpusFile OggOpusFile;

#define OP_HOLE (-3)
#define OP_EFAULT (-129)

OggOpusFile *op_open_file(const char *_path, int *_error);
void op_free(OggOpusFile *_of);
int op_read(OggOpusFile *_of, opus_int16 *_pcm, int _buf_size, int *_li);
/* Total PCM sample count at 48 kHz. `_li` of -1 means the whole stream.
   Declared as int64_t; libopusfile's ogg_int64_t is int64_t on Apple platforms. */
int64_t op_pcm_total(const OggOpusFile *_of, int _li);
