import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class OpenRequests {
    var items: [OpenItem] = []
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let openRequests = OpenRequests()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openRequests.items += urls.map { OpenItem(url: $0) }
    }
}

@main
struct MacdowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Macdow", id: "main") {
            ContentView()
                .environment(model)
                .environment(appDelegate.openRequests)
                .frame(minWidth: 920, minHeight: 600)
        }

        Settings {
            AppSettingsView()
                .environment(model)
        }
    }
}
