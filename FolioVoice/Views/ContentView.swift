import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: SpeechPlayer
    @State private var showingImporter = false
    @State private var showingPlayer = false
    @State private var documentToDelete: ReadingDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    brandHeader
                    introduction
                    if library.isImporting { importStatus }
                    librarySection
                    Label("Your files and voice stay on your iPhone.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(FolioTheme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .background(FolioTheme.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.document != nil {
                    miniPlayer
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .tint(FolioTheme.violet)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { library.importPDF(from: url) }
            case .failure(let error):
                library.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingPlayer) {
            ReaderView()
                .environmentObject(library)
                .environmentObject(player)
        }
        .alert("Library needs attention", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "Please try another PDF.")
        }
        .confirmationDialog("Remove this PDF from your library?", isPresented: Binding(get: { documentToDelete != nil }, set: { if !$0 { documentToDelete = nil } }), titleVisibility: .visible) {
            Button("Remove PDF", role: .destructive) {
                if let document = documentToDelete { library.remove(document) }
                documentToDelete = nil
            }
            Button("Cancel", role: .cancel) { documentToDelete = nil }
        } message: {
            Text("The original file will stay where you imported it from.")
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FolioTheme.violet)
                .frame(width: 34, height: 34)
                .background(FolioTheme.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            Text("folio voice")
                .font(.system(.title3, design: .serif, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(FolioTheme.ink)
            Spacer()
            Text("READ. LISTEN. REPEAT.")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(FolioTheme.muted)
                .accessibilityHidden(true)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    introductionText
                    BookArtwork().frame(width: 124, height: 144)
                }
                introductionText
            }
            Button {
                showingImporter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                    Text("Import a PDF")
                    Spacer()
                    Image(systemName: "arrow.up.doc")
                }
                .font(.system(.body, weight: .semibold))
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .foregroundStyle(Color.white)
                .background(Color(red: 0.42, green: 0.34, blue: 0.72), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(library.isImporting)
            .opacity(library.isImporting ? 0.6 : 1)
            .accessibilityHint("Choose a PDF from Files to add to your library")
        }
    }

    private var introductionText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Every page,\nout loud.")
                .font(.system(.largeTitle, design: .serif, weight: .medium))
                .tracking(-1.2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(FolioTheme.ink)
            Text("Your PDFs. Your pace.\nA voice that feels right.")
                .font(.subheadline)
                .lineSpacing(4)
                .foregroundStyle(FolioTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                Text(library.importStatus.isEmpty ? "Preparing your PDF…" : library.importStatus)
                    .font(.subheadline)
                    .foregroundStyle(FolioTheme.ink)
                Spacer(minLength: 4)
                Button("Cancel") { library.cancelImport() }
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
            }
            ProgressView(value: library.importProgress)
                .accessibilityLabel("Import progress")
            Text("Large or scanned documents may take a moment.")
                .font(.caption)
                .foregroundStyle(FolioTheme.muted)
        }
        .folioCard()
        .accessibilityElement(children: .combine)
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your library")
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .foregroundStyle(FolioTheme.ink)
                Spacer()
                Text(library.documents.count == 1 ? "1 document" : "\(library.documents.count) documents")
                    .font(.caption)
                    .foregroundStyle(FolioTheme.muted)
            }
            if library.documents.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 29, weight: .light))
                        .foregroundStyle(FolioTheme.violet)
                        .frame(width: 66, height: 66)
                        .background(FolioTheme.violet.opacity(0.08), in: Circle())
                    VStack(spacing: 7) {
                        Text("A little space for your next read.")
                            .font(.system(.headline, design: .serif))
                            .foregroundStyle(FolioTheme.ink)
                        Text("Add a paper, a story, or that PDF you’ve been meaning to get to.")
                            .font(.subheadline)
                            .foregroundStyle(FolioTheme.muted)
                            .lineSpacing(3)
                    }
                    .multilineTextAlignment(.center)
                    Text("PDFs with text and scanned pages supported")
                        .font(.caption)
                        .foregroundStyle(FolioTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .folioCard(padding: 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(library.documents) { document in
                        Button {
                            player.open(document)
                            showingPlayer = true
                        } label: {
                            DocumentRow(document: document, isCurrent: player.document?.id == document.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { documentToDelete = document } label: {
                                Label("Remove from library", systemImage: "trash")
                            }
                        }
                        .accessibilityAction(named: "Remove from library") { documentToDelete = document }
                    }
                }
            }
        }
    }

    private var miniPlayer: some View {
        HStack(spacing: 12) {
            Button { showingPlayer = true } label: {
                HStack(spacing: 12) {
                    SoundWave(height: 24)
                        .frame(width: 44, height: 44)
                        .background(FolioTheme.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.document?.title ?? "Your reading")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(FolioTheme.ink)
                        Text(player.isPlaying ? "Reading · Page \(player.currentPage)" : (player.isFinished ? "Finished" : "Ready when you are"))
                            .font(.caption)
                            .foregroundStyle(FolioTheme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open reader")
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : (player.isFinished ? "arrow.counterclockwise" : "play.fill"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FolioTheme.violet)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause reading" : (player.isFinished ? "Read again" : "Play reading"))
        }
        .padding(12)
        .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(FolioTheme.line, lineWidth: 1))
    }
}

private struct DocumentRow: View {
    let document: ReadingDocument
    let isCurrent: Bool
    @State private var chunkCount: Int?

    private var readingProgress: Double? {
        guard let chunkCount, chunkCount > 0 else { return nil }
        return min(1, Double(document.chunkIndex) / Double(chunkCount))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            BookArtwork(compact: true)
                .frame(width: 64, height: 78)
            VStack(alignment: .leading, spacing: 7) {
                Text(document.title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(FolioTheme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text("\(document.pageCount) \(document.pageCount == 1 ? "page" : "pages") · PDF")
                    .font(.caption)
                    .foregroundStyle(FolioTheme.muted)
                if document.isFinished {
                    Label("Finished", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(FolioTheme.violet)
                } else if let readingProgress, readingProgress > 0 {
                    ProgressView(value: readingProgress)
                        .tint(FolioTheme.violet)
                        .accessibilityLabel("Reading progress")
                } else {
                    Text(document.chunkIndex > 0 ? "Continue listening" : (isCurrent ? "Ready to listen" : "Tap to start listening"))
                        .font(.caption)
                        .foregroundStyle(FolioTheme.violet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FolioTheme.muted)
                .accessibilityHidden(true)
        }
        .folioCard(padding: 16)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open document and reading controls")
        .task(id: document.id) {
            // Pages are immutable. Cache this work instead of splitting the whole PDF
            // again whenever playback updates its saved position.
            let pages = document.pages
            let count = await Task.detached(priority: .utility) {
                TextChunker.chunks(from: pages).count
            }.value
            guard !Task.isCancelled else { return }
            chunkCount = count
        }
    }
}
