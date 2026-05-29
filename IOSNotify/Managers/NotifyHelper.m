#import "NotifyHelper.h"
#import <notify.h>

@implementation NotifyHelper

// Last time a screen-on event was delivered to the handler. Used to debounce
// the two registered notifications which may both fire within milliseconds of
// the same wake event.
static NSDate *_lastFire = nil;
static const NSTimeInterval kDebounce = 1.5;

+ (void)observeScreenOnWithHandler:(dispatch_block_t)handler {

    // ── Display power-state ─────────────────────────────────────────────────
    // "com.apple.iokit.hid.displayStatus" fires when the backlight changes
    // state.  state != 0 means the display just turned ON.  This fires for
    // BOTH locked-screen wakes and already-unlocked wakes, making it the
    // primary signal for "user woke the screen".
    int dispToken = -1;
    notify_register_dispatch(
        "com.apple.iokit.hid.displayStatus",
        &dispToken,
        dispatch_get_main_queue(),
        ^(int tok) {
            uint64_t state = 0;
            notify_get_state(tok, &state);
            if (state != 0) {
                [NotifyHelper fireIfDebounced:handler];
            }
        }
    );

    // ── Springboard lock-state ──────────────────────────────────────────────
    // "com.apple.springboard.lockstate": state == 0 means the phone just
    // became unlocked (screen already on).  Catches unlock events that
    // displayStatus does not re-fire for (display was never off).
    int lockToken = -1;
    notify_register_dispatch(
        "com.apple.springboard.lockstate",
        &lockToken,
        dispatch_get_main_queue(),
        ^(int tok) {
            uint64_t state = 0;
            notify_get_state(tok, &state);
            if (state == 0) {
                [NotifyHelper fireIfDebounced:handler];
            }
        }
    );
}

+ (void)fireIfDebounced:(dispatch_block_t)handler {
    NSDate *now = [NSDate date];
    if (_lastFire == nil || [now timeIntervalSinceDate:_lastFire] > kDebounce) {
        _lastFire = now;
        handler();
    }
}

@end
