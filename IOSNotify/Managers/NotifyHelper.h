#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NotifyHelper : NSObject

/// Calls handler whenever the display turns on — covers both locked-screen wakes
/// (display power-state notification) and unlock events (springboard lockstate).
/// Duplicate fires within 1.5 s are coalesced to prevent double-triggering.
+ (void)observeScreenOnWithHandler:(dispatch_block_t)handler;

@end

NS_ASSUME_NONNULL_END
