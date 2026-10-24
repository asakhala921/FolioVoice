import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: SpeechPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingVoices = false
    @State private var showingOriginal = false
    @State private var isScrubbing = false
    @State private var scrubbedChunk = 0.0

    private var controlsInScroll: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    title
                    Picker("Document view", selection: $showingOriginal) {
                        Text("Read along").tag(false)
                        Text("Original PDF").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if showingOriginal {
                        originalDocument
                    } else {
                        readingPassage
                    }
                    passageNavigation
                    if controlsInScroll {
                        controls.padding(.horizontal, -24)
                    }
                }
                .padding(24)
                .padding(.bottom, 8)
            }
            .background(FolioTheme.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !controlsInScroll { controls }
            }
        }
        .tint(FolioTheme.violet)
        .sheet(isPresented: $showingVoices) {
            VoicePickerView().environmentObject(player)
        }
        .alert("Reading paused", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            Button("OK", role: .cancel) { player.errorMessage = nil }
        } message: {
            Text(player.errorMessage ?? "Please try again.")
        }
    }

    private var header: some View {
        HStack {
            RoundIconButton(symbol: "chevron.down", label: "Close reader") { dismiss() }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(player.isPlaying ? FolioTheme.apricot : FolioTheme.muted).frame(width: 6, height: 6)
                Text(player.isPlaying ? "NOW READING" : (player.isFinished ? "ALL FINISHED" : "YOUR READING SPACE"))
                    .font(.system(.caption2, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(FolioTheme.muted)
            }
            Spacer()
            Image(systemName: "headphones")
                .font(.system(size: 18))
                .foregroundStyle(FolioTheme.violet)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var title: some View {
        HStack(alignment: .center, spacing: 18) {
            BookArtwork(compact: true)
                .frame(width: 72, height: 90)
            VStack(alignment: .leading, spacing: 8) {
                Text(player.document?.title ?? "Your PDF")
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .foregroundStyle(FolioTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(player.document?.pageCount ?? 0) pages · One page at a time")
                    .font(.caption)
                    .foregroundStyle(FolioTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var readingPassage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("PAGE \(player.currentPage)")
                    .font(.system(.caption2, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(FolioTheme.violet)
                Spacer()
                Image(systemName: "text.alignleft")
                    .foregroundStyle(FolioTheme.muted)
                    .accessibilityHidden(true)
            }
            if let chunk = player.currentChunk {
                Text(highlightedText(chunk.text))
                    .font(.system(.title3, design: .serif))
                    .lineSpacing(8)
                    .foregroundStyle(FolioTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .id(chunk.id)
                    .accessibilityLabel(chunk.text)
            } else {
                Text("There’s no readable text in this document.")
                    .font(.body)
                    .foregroundStyle(FolioTheme.muted)
            }
            if player.isFinished {
                Label("You’ve reached the last page.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(FolioTheme.violet)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .folioCard(padding: 24)
    }

    @ViewBuilder
    private var originalDocument: some View {
        if let document = player.document, let url = library.url(for: document) {
            PDFDocumentView(url: url, pageNumber: player.currentPage)
                .frame(minHeight: 350, idealHeight: 450)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(FolioTheme.line, lineWidth: 1))
                .accessibilityLabel("Original PDF, page \(player.currentPage)")
        } else {
            ContentUnavailableView("PDF unavailable", systemImage: "doc.questionmark", description: Text("Try importing the original file again."))
                .frame(minHeight: 280)
        }
    }

    private var passageNavigation: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Page \(player.currentPage) of \(player.document?.pageCount ?? 0)")
                Spacer()
                Text(player.isFinished ? "Finished" : "\(Int(player.progress * 100))%")
            }
            .font(.caption)
            .foregroundStyle(FolioTheme.muted)
            Slider(value: Binding(get: {
                isScrubbing ? scrubbedChunk : Double(player.chunkIndex)
            }, set: { value in
                scrubbedChunk = value
            }), in: 0...Double(max(1, player.chunks.count - 1)), step: 1) { editing in
                if editing {
                    scrubbedChunk = Double(player.chunkIndex)
                    isScrubbing = true
                } else {
                    isScrubbing = false
                    player.seek(toChunk: Int(scrubbedChunk))
                }
            }
            .disabled(player.chunks.count < 2)
            .accessibilityLabel("Reading position")
            .accessibilityValue("Passage \(player.chunkIndex + 1) of \(player.chunks.count)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: player.skip(by: 1)
                case .decrement: player.skip(by: -1)
                @unknown default: break
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 32) {
                Button { player.skip(by: -1) } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 23))
                        .frame(width: 52, height: 52)
                }
                .disabled(player.chunkIndex <= 0)
                .accessibilityLabel("Previous passage")
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : (player.isFinished ? "arrow.counterclockwise" : "play.fill"))
                        .font(.system(size: 25, weight: .semibold))
                        .offset(x: !player.isPlaying && !player.isFinished ? 2 : 0)
                        .frame(width: 72, height: 72)
                        .foregroundStyle(Color.white)
                        .background(Color(red: 0.42, green: 0.34, blue: 0.72), in: Circle())
                }
                .disabled(player.currentChunk == nil)
                .accessibilityLabel(player.isPlaying ? "Pause reading" : (player.isFinished ? "Read again" : "Play reading"))
                Button { player.skip(by: 1) } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 23))
                        .frame(width: 52, height: 52)
                }
                .disabled(player.chunkIndex >= player.chunks.count - 1)
                .accessibilityLabel("Next passage")
            }
            .buttonStyle(.plain)
            .foregroundStyle(FolioTheme.ink)
            .frame(maxWidth: .infinity)
            speedControl
            Button { showingVoices = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.wave.2")
                        .foregroundStyle(FolioTheme.violet)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.selectedVoice?.name ?? "System voice")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FolioTheme.ink)
                        Text(player.selectedVoice?.accent ?? "Choose a voice and accent")
                            .font(.caption)
                            .foregroundStyle(FolioTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FolioTheme.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                .background(FolioTheme.violet.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice and accent, \(player.selectedVoice?.name ?? "System voice"), \(player.selectedVoice?.accent ?? "")")
            .accessibilityHint("Choose an installed voice or preview accents")
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(FolioTheme.card)
        .overlay(alignment: .top) { Rectangle().fill(FolioTheme.line).frame(height: 1) }
    }

    private var speedControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "tortoise")
                .foregroundStyle(FolioTheme.muted)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { player.speed }, set: { player.setSpeed($0) }), in: 0.5...2, step: 0.1)
                .accessibilityLabel("Reading speed")
                .accessibilityValue("\(player.speed.formatted(.number.precision(.fractionLength(1)))) times")
            Text("\(player.speed.formatted(.number.precision(.fractionLength(1))))×")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(FolioTheme.violet)
                .frame(minWidth: 42, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func highlightedText(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let spokenRange = player.spokenRange,
              spokenRange.location != NSNotFound,
              spokenRange.location >= 0,
              spokenRange.length > 0,
              spokenRange.location <= text.utf16.count,
              spokenRange.length <= text.utf16.count - spokenRange.location,
              let range = Range(spokenRange, in: text),
              let lower = AttributedString.Index(range.lowerBound, within: attributed),
              let upper = AttributedString.Index(range.upperBound, within: attributed) else { return attributed }
        attributed[lower..<upper].foregroundColor = FolioTheme.violet
        attributed[lower..<upper].backgroundColor = FolioTheme.violet.opacity(0.13)
        return attributed
    }
}
