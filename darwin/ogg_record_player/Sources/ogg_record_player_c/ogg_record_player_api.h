// Objective-C view of `OggRecordPlayerApi` (OggRecordPlayerApi.swift), read by `dart run tool/ffigen.dart` and by the
// generated wrapper ogg_record_player_darwin.m. It is private (not in include/), so it never clashes with the Swift
// class. Keep it identical to the Swift @objc API:
// selectors, parameter types and block signatures are matched at runtime.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OggRecordPlayerApi : NSObject

// engineId is the calling engine's `PlatformDispatcher.instance.engineId`, or 0 when Dart has none.
+ (void)setPlayerListenerForEngine:(int64_t)engineId listener:(nullable void (^)(NSInteger playerId, NSInteger state, double position, double duration, double speed, NSString *_Nullable errorCode))listener;
+ (void)setRecorderListenersForEngine:(int64_t)engineId
                             canceled:(nullable void (^)(NSInteger recorderId, NSInteger reason))canceled
                          startFailed:(nullable void (^)(NSInteger recorderId, NSString *error))startFailed
                             finished:(nullable void (^)(NSInteger recorderId, NSInteger durationMillis, NSData *waveform))finished;

+ (void)createFromFileForEngine:(int64_t)engineId path:(NSString *)path callback:(void (^)(NSInteger playerId, NSString *_Nullable code, NSString *_Nullable message, NSString *_Nullable details))callback;
+ (void)createFromUrlForEngine:(int64_t)engineId url:(NSString *)string callback:(void (^)(NSInteger playerId, NSString *_Nullable code, NSString *_Nullable message, NSString *_Nullable details))callback;
+ (void)createFromBytesForEngine:(int64_t)engineId bytes:(NSData *)bytes callback:(void (^)(NSInteger playerId, NSString *_Nullable code, NSString *_Nullable message, NSString *_Nullable details))callback;
+ (void)warmUp:(void (^)(void))callback;
+ (void)play:(NSInteger)playerId;
+ (void)pause:(NSInteger)playerId;
+ (void)stop:(NSInteger)playerId;
+ (void)getDuration:(NSInteger)playerId callback:(void (^)(BOOL known, double seconds))callback;
+ (void)setPlaybackSpeed:(NSInteger)playerId speed:(double)speed;

+ (NSInteger)createRecorderForEngine:(int64_t)engineId path:(NSString *)path;
+ (void)startRecord:(NSInteger)recorderId;
+ (void)stopRecord:(NSInteger)recorderId;
+ (void)destroyRecorder:(NSInteger)recorderId callback:(void (^)(void))callback;

@end

NS_ASSUME_NONNULL_END
