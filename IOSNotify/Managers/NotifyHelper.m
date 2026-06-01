#import "NotifyHelper.h"
#import <notify.h>

@implementation NotifyHelper

static NSDate *_lastFire = nil;
static const NSTimeInterval kDebounce = 1.5;

// YES while the springboard lock screen is showing (phone not yet unlocked).
// Starts as YES so the very first displayStatus wake is not suppressed before
// the lockstate notification has had a chance to update this flag.
static BOOL _isPhoneLocked = YES;

+ (void)observeScreenOnWithHandler:(dispatch_block_t)handler {

    // ── Lock-state tracker ──────────────────────────────────────────────────
    // state == 0  →  phone unlocked
    // state == 1  →  phone locked (lock screen showing)
    // We only update the flag here; we do NOT fire the screen-on handler on
    // unlock, because the user only wants the shortcut to run from the lock
    // screen, not when the phone is being actively used.
    int lockToken = -1;
    notify_register_dispatch(
        "com.apple.springboard.lockstate",
        &lockToken,
        dispatch_get_main_queue(),
        ^(int tok) {
            uint64_t state = 0;
            notify_get_state(tok, &state);
            _isPhoneLocked = (state != 0);
        }
    );

    // ── Display power-state ─────────────────────────────────────────────────
    // Fires whenever the backlight changes.  state != 0 = display turned ON.
    // We only forward the event when the lock screen is showing so that wakes
    // while the app is in the foreground (phone already unlocked) are ignored.
    int dispToken = -1;
    notify_register_dispatch(
        "com.apple.iokit.hid.displayStatus",
        &dispToken,
        dispatch_get_main_queue(),
        ^(int tok) {
            uint64_t state = 0;
            notify_get_state(tok, &state);
            if (state != 0 && _isPhoneLocked) {
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
