#ifndef opusenc_set_bitrate_h
#define opusenc_set_bitrate_h

#include <opusenc.h>

// Swift does not import variadic C functions, so ope_encoder_ctl is wrapped here.
int ope_encoder_set_bitrate(OggOpusEnc *enc, int bitrate);

#endif /* opusenc_set_bitrate_h */
