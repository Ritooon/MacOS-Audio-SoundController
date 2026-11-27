import Foundation
import Testing
@testable import Orpheus

@Suite("SettingsStore")
struct SettingsStoreTests {
    private func makeStore() -> SettingsStore {
        let suite = "OrpheusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!  // A fresh suite name always succeeds.
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults)
    }

    @Test func unknownAppHasNoSavedVolume() {
        let store = makeStore()
        #expect(store.appVolume(for: "com.example.app") == nil)
        #expect(!store.isAppMuted("com.example.app"))
    }

    @Test func volumeIsSavedPerApp() {
        let store = makeStore()
        store.setAppVolume(1.5, for: "com.example.a")
        store.setAppVolume(0.25, for: "com.example.b")

        #expect(store.appVolume(for: "com.example.a") == 1.5)
        #expect(store.appVolume(for: "com.example.b") == 0.25)
    }

    @Test func unityVolumeRemovesTheEntry() {
        let store = makeStore()
        store.setAppVolume(2, for: "com.example.a")
        store.setAppVolume(1, for: "com.example.a")

        #expect(store.appVolume(for: "com.example.a") == nil)
    }

    @Test func muteIsSavedAndCleared() {
        let store = makeStore()
        store.setAppMuted(true, for: "com.example.a")
        #expect(store.isAppMuted("com.example.a"))

        store.setAppMuted(false, for: "com.example.a")
        #expect(!store.isAppMuted("com.example.a"))
    }
}
