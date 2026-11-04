import SwiftUI

@main
struct PhonePadApp: App {
    init() {
        // A controller must not let the screen dim and lock mid-game.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
