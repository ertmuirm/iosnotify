import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = BluetoothManager.shared
        // Boot the automation engine on the main actor; it self-evaluates conditions on init.
        Task { @MainActor in _ = AutomationManager.shared }
        return true
    }
}
