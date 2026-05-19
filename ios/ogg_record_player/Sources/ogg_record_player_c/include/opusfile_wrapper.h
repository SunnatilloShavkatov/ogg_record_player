#pragma once
#include "opus.h"

typedef struct OggOpusFile OggOpusFile;

#define OP_HOLE (-3)
#define OP_EFAULT (-129)

OggOpusFile *op_open_file(const char *_path, int *_error);
void op_free(OggOpusFile *_of);
int op_read(OggOpusFile *_of, opus_int16 *_pcm, int _buf_size, int *_li);
