import SwiftUI

@main
struct KittyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar agent — no main window scene. A Settings scene exists
        // so SwiftUI is happy, but it's empty by design.
        Settings {
            EmptyView()
        }
    }
}
