#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LockStateHandler)(BOOL screenIsOn);

/// Wraps notify_register_dispatch so Swift can observe the screen lock state
/// without needing notify.h in the Swift module directly.
@interface NotifyHelper : NSObject
+ (void)observeLockStateWithHandler:(LockStateHandler)handler;
@end

NS_ASSUME_NONNULL_END
