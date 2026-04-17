# IOSNotify

An unsigned iOS app that routes notifications from any app to a FitPro-compatible smart band and the iOS Shortcuts app. Built for sideloading via SideStore.

## What it does

- **Smart band forwarding** — when a notification arrives, IOSNotify sends it to your paired FitPro-compatible band over BLE using the FitPro GATT protocol (service `FFF0`, write characteristic `FFF6`).
- **Shortcuts integration** — exposes a `Forward Notification` AppIntent so you can wire up Shortcuts automations that trigger on any app's notifications and pass them through IOSNotify.
- **Per-app control** — a simple text-only UI lets you choose which apps forward to the band, which fire as Shortcut triggers, or both.
- **Notification log** — keeps a scrollable history of every forwarded notification, filterable by destination.

## How notification forwarding works on iOS

iOS sandboxing prevents apps from reading other apps' notifications directly. IOSNotify uses the standard mechanism that watch companion apps (Fitbit, Garmin, etc.) rely on:

1. You create a **Shortcuts automation** for each app you want to monitor.
   - Trigger: `App → [App name] → Notification received`
   - Action: `IOSNotify → Forward Notification` (fill in App Name, Title, Body from the notification)
2. When that notification fires, Shortcuts calls the IOSNotify intent in the background.
3. IOSNotify forwards the payload to the band over BLE and/or logs it as a trigger event.

For notifications sent directly to IOSNotify itself, `UNUserNotificationCenterDelegate` is also implemented and will forward them automatically without a Shortcuts step.

## BLE protocol

IOSNotify targets bands that use the FitPro / generic OEM GATT profile:

| Role | UUID |
|------|------|
| Service | `FFF0` |
| Write characteristic | `FFF6` |
| Notify characteristic | `FFF7` |

Notification packet format: `AB 00 [len] 82 00 [category] 01 [title\0] [body\0]`

Category bytes are mapped automatically by app name (WhatsApp, Instagram, Facebook, Twitter, SMS, Email, generic).

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
| Notifications | Receive and process notifications routed via Shortcuts |
| Bluetooth | Connect to and communicate with your smart band |

## Setup guide

1. Grant notification permissions when prompted (or via Settings → IOSNotify → Notifications).
2. Open the **Device** tab and scan for your band. Tap it to connect.
3. Open the **Apps** tab and add the apps you want to monitor (display name + bundle ID).
   - Enable **Forward to band** and/or **Shortcut trigger** per app.
4. In the Shortcuts app, create an automation per monitored app:
   - Trigger: `App → [App] → Notification Received`
   - Action: `IOSNotify → Forward Notification`
   - Set parameters: App Name, Bundle ID, Title (`Notification Title`), Body (`Notification Body`)
5. Notifications from those apps will now appear on your band and in the IOSNotify log.
