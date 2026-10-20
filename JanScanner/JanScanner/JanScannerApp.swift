import SwiftUI

@main
struct JanScannerApp: App {
    @StateObject private var store = ScanStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .environmentObject(store)
                    .tabItem { Label("スキャン", systemImage: "barcode.viewfinder") }
                PhotoCheckView()
                    .tabItem { Label("写真で確認", systemImage: "photo") }
            }
        }
    }
}
