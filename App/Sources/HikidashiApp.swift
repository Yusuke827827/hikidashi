// Hikidashi の iOS アプリ本体。画面はすべて HikidashiUI（HikidashiCore）にある。

import HikidashiUI
import SwiftUI

@main
struct HikidashiApp: App {
    var body: some Scene {
        WindowGroup {
            HikidashiRootView()
        }
    }
}
