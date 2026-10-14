import SwiftUI

@main
struct HeadroomApp: App {
    @State private var store = UsageStore()

    init() {
        #if DEBUG
        Snapshot.runIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            UsageView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
