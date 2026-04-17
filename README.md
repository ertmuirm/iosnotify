# IOSNotify

An unsigned iOS app (iOS 17+) that routes notifications from any app to a FitPro-compatible smart band and fires as a trigger in the iOS Shortcuts app. Built for sideloading via SideStore.

## What it does

- **Smart band forwarding** — when a notification arrives, IOSNotify sends it to your paired FitPro-compatible band over BLE using the FitPro GATT protocol (service `FFF0`, write characteristic `FFF6`).
- **Shortcuts trigger** — IOSNotify appears as a native trigger in the Shortcuts app. When it detects a notification from a monitored app, it fires a Shortcuts automation — no manual action call needed.
- **Per-app control** — a text-only UI lets you choose which apps forward to the band, which fire as Shortcut triggers, or both.
- **Notification log** — scrollable history of every forwarded notification, filterable by band or Shortcut.

## How notification forwarding works on iOS

iOS sandboxing prevents apps from reading other apps' notifications directly. IOSNotify uses `UNUserNotificationCenterDelegate` for notifications delivered to it, and fires iOS 17 `AutomationTrigger` events that Shortcuts automations can react to.

For notifications delivered to IOSNotify itself, BLE forwarding and trigger events fire automatically. For other apps, the system routes the notification through Shortcuts using the built-in `App → Notification Received` automation trigger, which IOSNotify then picks up via its own trigger parameter.

## Shortcuts integration

IOSNotify appears as a **trigger source** in Shortcuts — not an action. The user experience:

1. Open Shortcuts → Automation → New Automation
2. Scroll to **IOSNotify** → tap **Notification Received**
3. In the parameter picker, select which app to listen to (populated from your Apps tab)
4. Add any actions you want to run when that notification arrives
5. IOSNotify fires the automation the moment it detects the notification

## BLE protocol

IOSNotify targets bands that use the FitPro / generic OEM GATT profile:

| Role | UUID |
|------|------|
| Service | `FFF0` |
| Write characteristic | `FFF6` |
| Notify characteristic | `FFF7` |

Notification packet format: `AB 00 [len] 82 00 [category] 01 [title\0] [body\0]`

Category bytes are mapped automatically by app name (WhatsApp, Instagram, Facebook, Twitter, SMS, Email, generic).

## Requirements

- iOS 17.0 or later (required for `AutomationTrigger`)
- A FitPro-compatible smart band
- SideStore (for sideloading the unsigned IPA)

## Installation via SideStore

1. Download `IOSNotify.ipa` from the latest GitHub Actions artifact.
2. Open SideStore on your iPhone.
3. Tap `+` and select the IPA file.
4. SideStore signs it with your Apple ID and installs it.
5. Trust the developer certificate in Settings → General → VPN & Device Management.

## Building from source

Requirements: macOS with Xcode 15+, Homebrew.

```sh
brew install xcodegen
xcodegen generate
open IOSNotify.xcodeproj
```

Or trigger the GitHub Actions workflow (`Build iOS IPA`) to produce an unsigned IPA artifact.

## Permissions required

| Permission | Reason |
|------------|--------|
| Notifications | Receive and process notifications |
| Bluetooth | Connect to and communicate with your smart band |

## Setup guide

1. Grant notification permissions when prompted (or via Settings → IOSNotify → Notifications).
2. Open the **Device** tab and scan for your band. Tap it to connect.
3. Open the **Apps** tab and add the apps you want to monitor (display name + bundle ID).
   - Enable **Forward to band** to push notifications to your band over BLE.
   - Enable **Shortcut trigger** to make those notifications fire your Shortcuts automations.
4. In the Shortcuts app, create an automation per monitored app:
   - Trigger: **IOSNotify → Notification Received** → select the app
   - Add your desired actions
5. Notifications from those apps will appear on your band and in the IOSNotify log.
