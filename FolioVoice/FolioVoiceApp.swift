import SwiftUI

@main
struct FolioVoiceApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var player: SpeechPlayer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = LibraryStore()
        let speech = SpeechPlayer()
        speech.onProgress = { [weak store] document in store?.updateProgress(document) }
        store.onRemove = { [weak speech] id in
            if speech?.document?.id == id { speech?.close() }
        }
        _library = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: speech)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .onOpenURL { library.importPDF(from: $0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { player.refreshVoices() }
                    if phase == .background { library.flush() }
                }
        }
    }
}
