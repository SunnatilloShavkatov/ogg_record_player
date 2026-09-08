#include <jni.h>
#include <stdio.h>
#include <opus.h>
#include <opusenc.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <stdint.h>
#include "utils.h"

// Handles handed to Java are opaque generation ids, never raw pointers: a stale
// id from an already-stopped recorder can never be resolved back to freed memory.
typedef struct OpusRecorderContext {
    uint64_t id;
    OggOpusEnc *enc;
    OggOpusComments *comments;
    pthread_mutex_t lock;   // serializes encoder calls for this context
    int is_stopped;
    int refs;               // guarded by g_registry_lock
    struct OpusRecorderContext *next;
} OpusRecorderContext;

static pthread_mutex_t g_registry_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_registry_cond = PTHREAD_COND_INITIALIZER;
static OpusRecorderContext *g_contexts = NULL;
static uint64_t g_next_id = 1;

// Resolves a handle and pins the context so it cannot be freed while in use.
// Returns NULL if the handle is unknown or already unlinked by stopRecord.
static OpusRecorderContext *ctx_acquire(jlong handle) {
    if (handle <= 0) {
        return NULL;
    }
    uint64_t id = (uint64_t) handle;
    OpusRecorderContext *found = NULL;
    pthread_mutex_lock(&g_registry_lock);
    for (OpusRecorderContext *it = g_contexts; it != NULL; it = it->next) {
        if (it->id == id) {
            found = it;
            found->refs++;
            break;
        }
    }
    pthread_mutex_unlock(&g_registry_lock);
    return found;
}

static void ctx_release(OpusRecorderContext *ctx) {
    pthread_mutex_lock(&g_registry_lock);
    if (--ctx->refs == 0) {
        pthread_cond_broadcast(&g_registry_cond);
    }
    pthread_mutex_unlock(&g_registry_lock);
}

static inline void set_bits(uint8_t *bytes, int32_t bitOffset, int32_t value) {
    bytes += bitOffset / 8;
    bitOffset %= 8;
    uint32_t mask = (uint32_t)(value & 31) << bitOffset;
    bytes[0] |= (uint8_t)(mask & 0xFF);
    bytes[1] |= (uint8_t)((mask >> 8) & 0xFF);
    bytes[2] |= (uint8_t)((mask >> 16) & 0xFF);
    bytes[3] |= (uint8_t)((mask >> 24) & 0xFF);
}

JNIEXPORT jlong JNICALL Java_uz_plugin_ogg_1opus_1player_OpusAudioRecorder_startRecord(JNIEnv *env, jobject thiz, jstring path) {
    if (!path) {
        LOGE("startRecord: path is NULL");
        return 0;
    }
    const char *pathStr = (*env)->GetStringUTFChars(env, path, 0);
    if (!pathStr) {
        LOGE("startRecord: GetStringUTFChars failed");
        return 0;
    }

    OpusRecorderContext *ctx = (OpusRecorderContext *)calloc(1, sizeof(OpusRecorderContext));
    if (!ctx) {
        LOGE("startRecord: Failed to allocate OpusRecorderContext");
        (*env)->ReleaseStringUTFChars(env, path, pathStr);
        return 0;
    }

    pthread_mutex_init(&ctx->lock, NULL);
    ctx->is_stopped = 0;
    ctx->refs = 0;

    ctx->comments = ope_comments_create();
    if (!ctx->comments) {
        LOGE("startRecord: Create OggOpusComments failed");
        pthread_mutex_destroy(&ctx->lock);
        free(ctx);
        (*env)->ReleaseStringUTFChars(env, path, pathStr);
        return 0;
    }

    int error = OPE_OK;
    ctx->enc = ope_encoder_create_file(pathStr, ctx->comments, 16000, 1, 0, &error);
    (*env)->ReleaseStringUTFChars(env, path, pathStr);

    if (error != OPE_OK || !ctx->enc) {
        LOGE("startRecord: Create OggOpusEnc failed with error: %d", error);
        ope_comments_destroy(ctx->comments);
        pthread_mutex_destroy(&ctx->lock);
        free(ctx);
        return 0;
    }

    error = ope_encoder_ctl(ctx->enc, OPUS_SET_BITRATE_REQUEST, 16 * 1024);
    if (error != OPE_OK) {
        LOGE("startRecord: Set bitrate failed with error: %d", error);
        ope_encoder_destroy(ctx->enc);
        ope_comments_destroy(ctx->comments);
        pthread_mutex_destroy(&ctx->lock);
        free(ctx);
        return 0;
    }

    pthread_mutex_lock(&g_registry_lock);
    ctx->id = g_next_id++;
    ctx->next = g_contexts;
    g_contexts = ctx;
    pthread_mutex_unlock(&g_registry_lock);

    return (jlong) ctx->id;
}

JNIEXPORT jint JNICALL Java_uz_plugin_ogg_1opus_1player_OpusAudioRecorder_writeFrame(JNIEnv *env, jobject thiz, jlong handle, jshortArray frame, jint len) {
    if (handle == 0) {
        LOGE("writeFrame: handle is 0, aborting write");
        return OPE_BAD_ARG;
    }
    if (frame == NULL || len <= 0) {
        LOGE("writeFrame: Invalid frame or length");
        return OPE_BAD_ARG;
    }

    OpusRecorderContext *ctx = ctx_acquire(handle);
    if (ctx == NULL) {
        LOGE("writeFrame: stale handle, aborting write");
        return OPE_BAD_ARG;
    }

    pthread_mutex_lock(&ctx->lock);
    if (ctx->is_stopped || ctx->enc == NULL) {
        pthread_mutex_unlock(&ctx->lock);
        ctx_release(ctx);
        LOGE("writeFrame: Encoder is stopped or NULL");
        return OPE_BAD_ARG;
    }

    jsize arrayLen = (*env)->GetArrayLength(env, frame);
    if (len > arrayLen) {
        len = arrayLen;
    }

    jshort *sampleBuffer = (*env)->GetShortArrayElements(env, frame, NULL);
    if (sampleBuffer == NULL) {
        pthread_mutex_unlock(&ctx->lock);
        ctx_release(ctx);
        LOGE("writeFrame: sampleBuffer is NULL");
        return OPE_BAD_ARG;
    }

    int result = ope_encoder_write(ctx->enc, sampleBuffer, len);
    (*env)->ReleaseShortArrayElements(env, frame, sampleBuffer, JNI_ABORT);

    pthread_mutex_unlock(&ctx->lock);
    ctx_release(ctx);
    return result;
}

JNIEXPORT void JNICALL Java_uz_plugin_ogg_1opus_1player_OpusAudioRecorder_stopRecord(JNIEnv *env, jobject thiz, jlong handle) {
    if (handle == 0) {
        return;
    }

    uint64_t id = (uint64_t) handle;
    OpusRecorderContext *ctx = NULL;

    // Unlink first so no new writeFrame can pin this context, then wait for the
    // writers already inside to drop their reference before freeing anything.
    pthread_mutex_lock(&g_registry_lock);
    for (OpusRecorderContext **it = &g_contexts; *it != NULL; it = &(*it)->next) {
        if ((*it)->id == id) {
            ctx = *it;
            *it = ctx->next;
            ctx->next = NULL;
            break;
        }
    }
    if (ctx == NULL) {
        pthread_mutex_unlock(&g_registry_lock);
        LOGE("stopRecord: stale handle, nothing to stop");
        return;
    }
    while (ctx->refs > 0) {
        pthread_cond_wait(&g_registry_cond, &g_registry_lock);
    }
    pthread_mutex_unlock(&g_registry_lock);

    pthread_mutex_lock(&ctx->lock);
    if (!ctx->is_stopped) {
        ctx->is_stopped = 1;
        if (ctx->enc != NULL) {
            ope_encoder_drain(ctx->enc);
            ope_encoder_destroy(ctx->enc);
            ctx->enc = NULL;
        }
        if (ctx->comments != NULL) {
            ope_comments_destroy(ctx->comments);
            ctx->comments = NULL;
        }
    }
    pthread_mutex_unlock(&ctx->lock);

    pthread_mutex_destroy(&ctx->lock);
    free(ctx);
    LOGI("stopRecord: ope encoder destroy completed and context freed");
}

JNIEXPORT jbyteArray JNICALL Java_uz_plugin_ogg_1opus_1player_OpusAudioRecorder_getWaveform2(JNIEnv *env, jobject thiz, jshortArray array, jint length) {
    if (array == NULL || length <= 0) {
        return NULL;
    }
    jsize arrayLen = (*env)->GetArrayLength(env, array);
    if (length > arrayLen) {
        length = arrayLen;
    }

    jshort *sampleBuffer = (*env)->GetShortArrayElements(env, array, NULL);
    if (sampleBuffer == NULL) {
        return NULL;
    }

    const int32_t resultSamples = 100;
    uint16_t *samples = (uint16_t *)calloc(resultSamples, sizeof(uint16_t));
    if (samples == NULL) {
        (*env)->ReleaseShortArrayElements(env, array, sampleBuffer, JNI_ABORT);
        return NULL;
    }

    uint64_t sampleIndex = 0;
    uint16_t peakSample = 0;
    int32_t sampleRate = (int32_t) max(1, length / resultSamples);
    int32_t index = 0;

    for (int32_t i = 0; i < length; i++) {
        int16_t raw = sampleBuffer[i];
        uint16_t sample = (raw == -32768) ? 32767 : (uint16_t) abs(raw);
        if (sample > peakSample) {
            peakSample = sample;
        }
        if (sampleIndex++ % sampleRate == 0) {
            if (index < resultSamples) {
                samples[index++] = peakSample;
            }
            peakSample = 0;
        }
    }

    int64_t sumSamples = 0;
    for (int32_t i = 0; i < resultSamples; i++) {
        sumSamples += samples[i];
    }
    uint16_t peak = (uint16_t) (sumSamples * 1.8f / resultSamples);
    if (peak < 2500) {
        peak = 2500;
    }

    for (int32_t i = 0; i < resultSamples; i++) {
        if (samples[i] > peak) {
            samples[i] = peak;
        }
    }

    (*env)->ReleaseShortArrayElements(env, array, sampleBuffer, JNI_ABORT);

    uint32_t bitStreamLength = resultSamples * 5 / 8 + 1;
    jbyteArray result = (*env)->NewByteArray(env, bitStreamLength);
    if (result) {
        uint8_t *bytes = (uint8_t *)calloc(bitStreamLength + 4, 1);
        if (bytes) {
            for (int32_t i = 0; i < resultSamples; i++) {
                int32_t value = min(31, abs((int32_t) samples[i]) * 31 / peak);
                set_bits(bytes, i * 5, value & 31);
            }
            (*env)->SetByteArrayRegion(env, result, 0, bitStreamLength, (jbyte *) bytes);
            free(bytes);
        }
    }

    free(samples);
    return result;
}