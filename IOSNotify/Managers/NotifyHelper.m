#import "NotifyHelper.h"
#import <notify.h>

@implementation NotifyHelper

+ (void)observeLockStateWithHandler:(LockStateHandler)handler {
    int token = -1;
    // state == 0 → display turning ON; state == 1 → display turning OFF / locked
    notify_register_dispatch(
        "com.apple.springboard.lockstate",
        &token,
        dispatch_get_main_queue(),
        ^(int tok) {
            uint64_t state = 0;
            notify_get_state(tok, &state);
            handler(state == 0);
        }
    );
}

@end
