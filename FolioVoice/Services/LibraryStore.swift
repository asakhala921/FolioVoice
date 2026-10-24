import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var documents: [ReadingDocument] = []
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress = 0.0
    @Published private(set) var importStatus = "Preparing your PDF…"
    @Published var errorMessage: String?
    var onRemove: ((UUID) -> Void)?

    private let repository: DocumentRepository?
    private let directory: URL
    private var loading: Task<Void, Never>?
    private var progressSaveTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var libraryLoaded = false

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolioVoice", isDirectory: true)
        do {
            repository = try DocumentRepository(directory: directory)
        } catch {
            repository = nil
            errorMessage = "Couldn’t open your library: \(error.localizedDescription)"
        }
        loading = Task { [weak self] in
            guard let self, let repository = self.repository else { return }
            do {
                self.documents = try await repository.load()
                    .sorted { $0.importedAt > $1.importedAt }
                self.libraryLoaded = true
            } catch {
                self.errorMessage = "Couldn’t read your saved library. Your PDF files have been kept. \(error.localizedDescription)"
            }
        }
    }

    func url(for document: ReadingDocument) -> URL? {
        let url = directory.appendingPathComponent(document.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func importPDF(from url: URL) {
        guard !isImporting else {
            errorMessage = "Please wait for the current PDF to finish importing."
            return
        }
        isImporting = true
        importProgress = 0
        importStatus = "Preparing your PDF…"
        importTask = Task { [weak self] in
            guard let self else { return }
            await self.loading?.value
            defer { self.isImporting = false; self.importTask = nil }
            guard self.libraryLoaded, let repository = self.repository else {
                self.errorMessage = "Your library couldn’t be loaded. Relaunch the app to try again; your saved files will be preserved."
                return
            }
            do {
                let document = try await repository.importPDF(from: url) { [weak self] page, total in
                    Task { @MainActor in
                        guard let self else { return }
                        self.importProgress = total > 0 ? Double(page) / Double(total) : 0
                        self.importStatus = "Reading page \(page) of \(total)…"
                    }
                }
                self.documents.insert(document, at: 0)
                self.flush()
            } catch is CancellationError {
                // Cancellation leaves the original document untouched.
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func remove(_ document: ReadingDocument) {
        guard libraryLoaded else { return }
        onRemove?(document.id)
        documents.removeAll { $0.id == document.id }
        progressSaveTask?.cancel()
        progressSaveTask = nil
        persist(documents, removing: document)
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func updateProgress(_ document: ReadingDocument) {
        guard libraryLoaded, let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index].chunkIndex = document.chunkIndex
        documents[index].utf16Offset = document.utf16Offset
        documents[index].isFinished = document.isFinished
        // Throttle instead of debounce: continuous speech must still save its place.
        guard progressSaveTask == nil else { return }
        progressSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self else { return }
            self.progressSaveTask = nil
            self.persist(self.documents)
        }
    }

    func flush() {
        guard libraryLoaded else { return }
        progressSaveTask?.cancel()
        progressSaveTask = nil
        persist(documents)
    }

    private func persist(_ snapshot: [ReadingDocument], removing document: ReadingDocument? = nil) {
        guard let repository else { return }
        let previousWrite = persistenceTask
        // Preserve mutation order even while PDF import, playback, and deletion overlap.
        persistenceTask = Task { [weak self] in
            await previousWrite?.value
            do {
                try await repository.save(snapshot)
                // Only delete the PDF after the manifest no longer references it.
                if let document { try await repository.removeFile(for: document) }
            } catch {
                self?.errorMessage = "Couldn’t save your library: \(error.localizedDescription)"
            }
        }
    }
}
