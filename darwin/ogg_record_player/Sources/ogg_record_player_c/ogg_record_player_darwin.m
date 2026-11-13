#include <stdint.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "ogg_record_player_api.h"

#if !__has_feature(objc_arc)
#error "This file must be compiled with ARC enabled"
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct {
  int64_t version;
  void* (*newWaiter)(void);
  void (*awaitWaiter)(void*);
  void* (*currentIsolate)(void);
  void (*enterIsolate)(void*);
  void (*exitIsolate)(void);
  int64_t (*getMainPortId)(void);
  bool (*getCurrentThreadOwnsIsolate)(int64_t);
  void (*invokeListenerPortBlock)(int64_t port, void*);
  void (*invokeBlockingPortBlock)(int64_t port, void*, void*);
} DOBJC_Context;

id objc_retainBlock(id);

#define BLOCKING_BLOCK_IMPL(ctx, TYPE, SIG, INVOKE_DIRECT, INVOKE_LISTENER)    \
  assert(ctx->version >= 1);                                                   \
  void* targetIsolate = ctx->currentIsolate();                                 \
  int64_t targetPort = ctx->getMainPortId == NULL ? 0 : ctx->getMainPortId();  \
  __block __weak TYPE weakSelfBlock = nil;                                     \
  TYPE strongSelfBlock = [SIG {                                                \
    void* currentIsolate = ctx->currentIsolate();                              \
    bool mayEnterIsolate =                                                     \
        currentIsolate == NULL &&                                              \
        ctx->getCurrentThreadOwnsIsolate != NULL &&                            \
        ctx->getCurrentThreadOwnsIsolate(targetPort);                          \
    if (currentIsolate == targetIsolate || mayEnterIsolate) {                  \
      if (mayEnterIsolate) {                                                   \
        ctx->enterIsolate(targetIsolate);                                      \
      }                                                                        \
      INVOKE_DIRECT;                                                           \
      if (mayEnterIsolate) {                                                   \
        ctx->exitIsolate();                                                    \
      }                                                                        \
    } else {                                                                   \
      void* waiter = ctx->newWaiter();                                         \
      TYPE selfRetain = [weakSelfBlock copy];                                  \
      INVOKE_LISTENER;                                                         \
      ctx->awaitWaiter(waiter);                                                \
      (void)selfRetain;                                                        \
    }                                                                          \
  } copy];                                                                     \
  weakSelfBlock = strongSelfBlock;                                             \
  return strongSelfBlock;


__attribute__((visibility("default")))
@interface _8ucdvo_BlockArgs_1pl9qdv : NSObject
@property (copy) id block;

@end
@implementation _8ucdvo_BlockArgs_1pl9qdv
@end

typedef void  (^_ListenerTrampoline)(void);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline _8ucdvo_wrapListenerBlock_1pl9qdv(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline weakSelfBlock = nil;
  _ListenerTrampoline strongSelfBlock = [^void() {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1pl9qdv* args = [[_8ucdvo_BlockArgs_1pl9qdv alloc] init];
      args.block = weakSelfBlock;
      
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline)(void * waiter);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline _8ucdvo_wrapBlockingBlock_1pl9qdv(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline, ^void(), {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1pl9qdv* args = [[_8ucdvo_BlockArgs_1pl9qdv alloc] init];
      args.block = weakSelfBlock;
      
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1pl9qdv* args = [[_8ucdvo_BlockArgs_1pl9qdv alloc] init];
      args.block = weakSelfBlock;
      
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _8ucdvo_BlockArgs_1w5k0al : NSObject
@property (copy) id block;
@property long arg0;
@property long arg1;
@end
@implementation _8ucdvo_BlockArgs_1w5k0al
@end

typedef void  (^_ListenerTrampoline_1)(long arg0, long arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_1 _8ucdvo_wrapListenerBlock_1w5k0al(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_1 weakSelfBlock = nil;
  _ListenerTrampoline_1 strongSelfBlock = [^void(long arg0, long arg1) {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1w5k0al* args = [[_8ucdvo_BlockArgs_1w5k0al alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_1)(void * waiter, long arg0, long arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_1 _8ucdvo_wrapBlockingBlock_1w5k0al(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_1, ^void(long arg0, long arg1), {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1w5k0al* args = [[_8ucdvo_BlockArgs_1w5k0al alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1w5k0al* args = [[_8ucdvo_BlockArgs_1w5k0al alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _8ucdvo_BlockArgs_o1oetf : NSObject
@property (copy) id block;
@property long arg0;
@property long arg1;
@property (strong) id arg2;
@end
@implementation _8ucdvo_BlockArgs_o1oetf
@end

typedef void  (^_ListenerTrampoline_2)(long arg0, long arg1, id arg2);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_2 _8ucdvo_wrapListenerBlock_o1oetf(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_2 weakSelfBlock = nil;
  _ListenerTrampoline_2 strongSelfBlock = [^void(long arg0, long arg1, id arg2) {
    @autoreleasepool {
      _8ucdvo_BlockArgs_o1oetf* args = [[_8ucdvo_BlockArgs_o1oetf alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_2)(void * waiter, long arg0, long arg1, id arg2);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_2 _8ucdvo_wrapBlockingBlock_o1oetf(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_2, ^void(long arg0, long arg1, id arg2), {
    @autoreleasepool {
      _8ucdvo_BlockArgs_o1oetf* args = [[_8ucdvo_BlockArgs_o1oetf alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _8ucdvo_BlockArgs_o1oetf* args = [[_8ucdvo_BlockArgs_o1oetf alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _8ucdvo_BlockArgs_rgwm94 : NSObject
@property (copy) id block;
@property long arg0;
@property long arg1;
@property double arg2;
@property double arg3;
@property double arg4;
@property (strong) id arg5;
@end
@implementation _8ucdvo_BlockArgs_rgwm94
@end

typedef void  (^_ListenerTrampoline_3)(long arg0, long arg1, double arg2, double arg3, double arg4, id arg5);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_3 _8ucdvo_wrapListenerBlock_rgwm94(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_3 weakSelfBlock = nil;
  _ListenerTrampoline_3 strongSelfBlock = [^void(long arg0, long arg1, double arg2, double arg3, double arg4, id arg5) {
    @autoreleasepool {
      _8ucdvo_BlockArgs_rgwm94* args = [[_8ucdvo_BlockArgs_rgwm94 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      args.arg4 = arg4;
      args.arg5 = arg5;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_3)(void * waiter, long arg0, long arg1, double arg2, double arg3, double arg4, id arg5);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_3 _8ucdvo_wrapBlockingBlock_rgwm94(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_3, ^void(long arg0, long arg1, double arg2, double arg3, double arg4, id arg5), {
    @autoreleasepool {
      _8ucdvo_BlockArgs_rgwm94* args = [[_8ucdvo_BlockArgs_rgwm94 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      args.arg4 = arg4;
      args.arg5 = arg5;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _8ucdvo_BlockArgs_rgwm94* args = [[_8ucdvo_BlockArgs_rgwm94 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      args.arg4 = arg4;
      args.arg5 = arg5;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _8ucdvo_BlockArgs_1kva9v1 : NSObject
@property (copy) id block;
@property long arg0;
@property (strong) id arg1;
@end
@implementation _8ucdvo_BlockArgs_1kva9v1
@end

typedef void  (^_ListenerTrampoline_4)(long arg0, id arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_4 _8ucdvo_wrapListenerBlock_1kva9v1(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_4 weakSelfBlock = nil;
  _ListenerTrampoline_4 strongSelfBlock = [^void(long arg0, id arg1) {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1kva9v1* args = [[_8ucdvo_BlockArgs_1kva9v1 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_4)(void * waiter, long arg0, id arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_4 _8ucdvo_wrapBlockingBlock_1kva9v1(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_4, ^void(long arg0, id arg1), {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1kva9v1* args = [[_8ucdvo_BlockArgs_1kva9v1 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1kva9v1* args = [[_8ucdvo_BlockArgs_1kva9v1 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _8ucdvo_BlockArgs_6r6s7t : NSObject
@property (copy) id block;
@property long arg0;
@property (strong) id arg1;
@property (strong) id arg2;
@property (strong) id arg3;
@end
@implementation _8ucdvo_BlockArgs_6r6s7t
@end

typedef void  (^_ListenerTrampoline_5)(long arg0, id arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_5 _8ucdvo_wrapListenerBlock_6r6s7t(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_5 weakSelfBlock = nil;
  _ListenerTrampoline_5 strongSelfBlock = [^void(long arg0, id arg1, id arg2, id arg3) {
    @autoreleasepool {
      _8ucdvo_BlockArgs_6r6s7t* args = [[_8ucdvo_BlockArgs_6r6s7t alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_5)(void * waiter, long arg0, id arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_5 _8ucdvo_wrapBlockingBlock_6r6s7t(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_5, ^void(long arg0, id arg1, id arg2, id arg3), {
    @autoreleasepool {
      _8ucdvo_BlockArgs_6r6s7t* args = [[_8ucdvo_BlockArgs_6r6s7t alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _8ucdvo_BlockArgs_6r6s7t* args = [[_8ucdvo_BlockArgs_6r6s7t alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _8ucdvo_BlockArgs_1c1zgbm : NSObject
@property (copy) id block;
@property BOOL arg0;
@property double arg1;
@end
@implementation _8ucdvo_BlockArgs_1c1zgbm
@end

typedef void  (^_ListenerTrampoline_6)(BOOL arg0, double arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_6 _8ucdvo_wrapListenerBlock_1c1zgbm(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_6 weakSelfBlock = nil;
  _ListenerTrampoline_6 strongSelfBlock = [^void(BOOL arg0, double arg1) {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1c1zgbm* args = [[_8ucdvo_BlockArgs_1c1zgbm alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_6)(void * waiter, BOOL arg0, double arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_6 _8ucdvo_wrapBlockingBlock_1c1zgbm(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_6, ^void(BOOL arg0, double arg1), {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1c1zgbm* args = [[_8ucdvo_BlockArgs_1c1zgbm alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _8ucdvo_BlockArgs_1c1zgbm* args = [[_8ucdvo_BlockArgs_1c1zgbm alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}
#undef BLOCKING_BLOCK_IMPL

#pragma clang diagnostic pop
