import SwiftUI

struct VoicePickerView: View {
    @EnvironmentObject private var player: SpeechPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredVoices: [VoiceOption] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return player.voices }
        return player.voices.filter { voice in
            [voice.name, voice.accent, voice.language, languageName(for: voice), voice.quality].contains {
                $0.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var accents: [String] {
        Array(Set(filteredVoices.map { groupName(for: $0) })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Make it sound like you.")
                            .font(.system(.title2, design: .serif))
                            .foregroundStyle(FolioTheme.ink)
                        Text("Choose a voice and accent, then tap the play button to hear a sample.")
                            .font(.subheadline)
                            .foregroundStyle(FolioTheme.muted)
                            .lineSpacing(3)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))

                if filteredVoices.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(accents, id: \.self) { accent in
                        Section(accent) {
                            ForEach(filteredVoices.filter { groupName(for: $0) == accent }) { voice in
                                voiceRow(voice)
                                    .listRowBackground(FolioTheme.card)
                            }
                        }
                    }
                }
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("More voices, more possibilities")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(FolioTheme.ink)
                            Text("Download additional voices in iPhone Settings → Accessibility → Spoken Content (or Read & Speak) → Voices. Return here after the download finishes. Voice availability varies by iOS version and language.")
                                .font(.caption)
                                .foregroundStyle(FolioTheme.muted)
                                .lineSpacing(3)
                        }
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(FolioTheme.violet)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(FolioTheme.violet.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
            .background(FolioTheme.canvas)
            .navigationTitle("Voice & accent")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search voice, language, or accent")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { player.refreshVoices() }
            .onDisappear { player.stopPreview() }
            .refreshable { player.refreshVoices() }
        }
        .tint(FolioTheme.violet)
    }

    private func languageName(for voice: VoiceOption) -> String {
        let languageCode = Locale(identifier: voice.language).language.languageCode?.identifier ?? voice.language
        return Locale.current.localizedString(forLanguageCode: languageCode) ?? voice.language
    }

    private func groupName(for voice: VoiceOption) -> String {
        "\(languageName(for: voice)) · \(voice.accent)"
    }

    private func voiceRow(_ voice: VoiceOption) -> some View {
        HStack(spacing: 10) {
            Button {
                player.stopPreview()
                player.selectVoice(voice.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: player.selectedVoiceID == voice.id ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 23, weight: .light))
                        .foregroundStyle(player.selectedVoiceID == voice.id ? FolioTheme.violet : FolioTheme.muted.opacity(0.4))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(voice.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(FolioTheme.ink)
                        Text(voice.quality.isEmpty ? languageName(for: voice) : "\(voice.quality) · \(languageName(for: voice))")
                            .font(.caption)
                            .foregroundStyle(FolioTheme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(voice.name), \(voice.accent), \(voice.quality)")
            .accessibilityAddTraits(player.selectedVoiceID == voice.id ? .isSelected : [])
            Button { player.previewVoice(voice.id) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FolioTheme.violet)
                    .frame(width: 44, height: 44)
                    .background(FolioTheme.violet.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(voice.name), \(voice.accent)")
        }
        .padding(.vertical, 3)
    }
}
