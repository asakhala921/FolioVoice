import Foundation
import Combine
@preconcurrency import AVFoundation
import MediaPlayer

struct VoiceOption: Identifiable {
    let id: String
    let name: String
    let language: String
    let accent: String
    let quality: String
}

@MainActor
final class SpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var document: ReadingDocument?
    @Published private(set) var chunks: [SpeechChunk] = []
    @Published private(set) var chunkIndex = 0
    @Published private(set) var spokenRange: NSRange?
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var speed: Double
    @Published private(set) var selectedVoiceID: String
    @Published private(set) var voices: [VoiceOption] = []
    @Published var errorMessage: String?
    var onProgress: ((ReadingDocument) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let previewSynthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var utteranceOffset = 0
    private var resumeOffset = 0
    private var chunkOffsets: [Int] = []
    private var totalTextLength = 0
    private var finished = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var resumeAfterInterruption = false

    var currentChunk: SpeechChunk? { chunks.indices.contains(chunkIndex) ? chunks[chunkIndex] : nil }
    var currentPage: Int { currentChunk?.pageNumber ?? 1 }
    var isFinished: Bool { finished }
    var selectedVoice: VoiceOption? { voices.first { $0.id == selectedVoiceID } }
    var progress: Double {
        guard !chunks.isEmpty else { return 0 }
        if finished { return 1 }
        let before = chunkOffsets.indices.contains(chunkIndex) ? chunkOffsets[chunkIndex] : 0
        return min(1, Double(before + resumeOffset) / Double(max(totalTextLength, 1)))
    }

    override init() {
        let savedSpeed = UserDefaults.standard.double(forKey: "playbackSpeed")
        speed = savedSpeed > 0 ? min(2, max(0.5, savedSpeed)) : 1
        selectedVoiceID = UserDefaults.standard.string(forKey: "voiceIdentifier") ?? ""
        super.init()
        synthesizer.delegate = self
        previewSynthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        previewSynthesizer.usesApplicationAudioSession = true
        refreshVoices()
        configureRemoteCommands()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in self?.handleInterruption(type: rawType, options: rawOptions) }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        for (command, target) in remoteTargets { command.removeTarget(target) }
    }

    func refreshVoices() {
        let locale = Locale.current
        voices = AVSpeechSynthesisVoice.speechVoices().map { voice in
            let voiceLocale = Locale(identifier: voice.language)
            let region = voiceLocale.region?.identifier
            let accent = region.flatMap { locale.localizedString(forRegionCode: $0) }
                ?? locale.localizedString(forIdentifier: voice.language) ?? voice.language
            let quality: String
            switch voice.quality {
            case .premium: quality = "Premium"
            case .enhanced: quality = "Enhanced"
            default: quality = "Standard"
            }
            return VoiceOption(id: voice.identifier, name: voice.name,
                               language: voice.language, accent: accent, quality: quality)
        }.sorted {
            let preferred = Locale.preferredLanguages.first?.prefix(2) ?? "en"
            let lhsPreferred = $0.language.hasPrefix(preferred)
            let rhsPreferred = $1.language.hasPrefix(preferred)
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            if $0.accent != $1.accent { return $0.accent.localizedStandardCompare($1.accent) == .orderedAscending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if !voices.contains(where: { $0.id == selectedVoiceID }) {
            let defaultVoice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
            selectedVoiceID = defaultVoice?.identifier ?? voices.first?.id ?? ""
            UserDefaults.standard.set(selectedVoiceID, forKey: "voiceIdentifier")
        }
    }

    func open(_ newDocument: ReadingDocument) {
        guard document?.id != newDocument.id else { return }
        checkpoint()
        stopSpeech()
        isPlaying = false
        stopPreview()
        resumeAfterInterruption = false
        document = newDocument
        chunks = newDocument.chunks
        totalTextLength = 0
        chunkOffsets = chunks.map { chunk in
            let offset = totalTextLength
            totalTextLength += chunk.text.utf16.count
            return offset
        }
        chunkIndex = min(max(0, newDocument.chunkIndex), max(0, chunks.count - 1))
        resumeOffset = safeOffset(newDocument.utf16Offset, in: currentChunk?.text ?? "")
        finished = newDocument.isFinished
        spokenRange = nil
        isPlaying = false
        isPaused = false
        updateNowPlaying()
    }

    func close() {
        stopSpeech()
        stopPreview()
        document = nil
        chunks = []
        chunkOffsets = []
        totalTextLength = 0
        chunkIndex = 0
        resumeOffset = 0
        spokenRange = nil
        finished = false
        isPlaying = false
        isPaused = false
        resumeAfterInterruption = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateAudio()
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard !chunks.isEmpty else { return }
        resumeAfterInterruption = false
        stopPreview()
        if finished {
            chunkIndex = 0
            resumeOffset = 0
            finished = false
            spokenRange = nil
        }
        guard activateAudio() else { return }
        // Recreate the utterance at the saved word. This also applies any changed voice or speed.
        stopSpeech()
        isPlaying = true
        isPaused = false
        speakCurrentChunk()
    }

    func pause() {
        resumeAfterInterruption = false
        guard isPlaying else { stopPreview(); return }
        stopSpeech()
        isPlaying = false
        isPaused = true
        checkpoint()
        updateNowPlaying()
        deactivateAudio()
    }

    func skip(by delta: Int) {
        seek(toChunk: chunkIndex + delta)
    }

    func seek(toChunk index: Int) {
        guard !chunks.isEmpty else { return }
        let wasPlaying = isPlaying
        stopSpeech()
        chunkIndex = min(max(0, index), chunks.count - 1)
        resumeOffset = 0
        spokenRange = nil
        finished = false
        checkpoint()
        if wasPlaying { speakCurrentChunk() }
        updateNowPlaying()
    }

    func setSpeed(_ value: Double) {
        guard value.isFinite else { return }
        let newSpeed = min(2, max(0.5, value))
        guard abs(speed - newSpeed) > 0.001 else { return }
        speed = newSpeed
        UserDefaults.standard.set(speed, forKey: "playbackSpeed")
        restartIfPlaying()
    }

    func selectVoice(_ id: String) {
        guard voices.contains(where: { $0.id == id }) else { return }
        selectedVoiceID = id
        UserDefaults.standard.set(id, forKey: "voiceIdentifier")
        stopPreview()
        restartIfPlaying()
    }

    func previewVoice(_ id: String) {
        guard let voice = AVSpeechSynthesisVoice(identifier: id) else { return }
        pause()
        previewSynthesizer.stopSpeaking(at: .immediate)
        guard activateAudio() else { return }
        let sample: String
        switch voice.language.prefix(2) {
        case "es": sample = "Hola. Esta es la voz que leerá tus documentos."
        case "fr": sample = "Bonjour. Voici la voix qui lira vos documents."
        case "de": sample = "Hallo. Diese Stimme liest Ihre Dokumente vor."
        case "it": sample = "Ciao. Questa voce leggerà i tuoi documenti."
        case "pt": sample = "Olá. Esta voz vai ler os seus documentos."
        case "hi": sample = "नमस्ते। यह आवाज़ आपके दस्तावेज़ पढ़ेगी।"
        case "ja": sample = "こんにちは。この声で文書を読み上げます。"
        case "zh": sample = "你好。我会用这个声音为你朗读文档。"
        default: sample = "Welcome to Folio Voice. Make a little room for listening."
        }
        let utterance = AVSpeechUtterance(string: sample)
        utterance.voice = voice
        utterance.rate = speechRate
        previewSynthesizer.speak(utterance)
    }

    func stopPreview() {
        previewSynthesizer.stopSpeaking(at: .immediate)
        if !isPlaying { deactivateAudio() }
    }

    private var speechRate: Float {
        min(AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
    }

    private func restartIfPlaying() {
        if isPlaying { stopSpeech(); speakCurrentChunk() }
        updateNowPlaying()
    }

    private func stopSpeech() {
        // Invalidate first: delayed callbacks from cancelled speech must not advance the new document.
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakCurrentChunk() {
        guard let chunk = currentChunk else { return }
        utteranceOffset = safeOffset(resumeOffset, in: chunk.text)
        let text = (chunk.text as NSString).substring(from: utteranceOffset)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID)
        utterance.rate = speechRate
        utterance.postUtteranceDelay = 0.12
        activeUtterance = utterance
        synthesizer.speak(utterance)
        checkpoint()
        updateNowPlaying()
    }

    private func safeOffset(_ offset: Int, in text: String) -> Int {
        let nsText = text as NSString
        guard nsText.length > 0 else { return 0 }
        let clamped = min(max(0, offset), nsText.length - 1)
        return nsText.rangeOfComposedCharacterSequence(at: clamped).location
    }

    private func checkpoint() {
        guard var updated = document else { return }
        updated.chunkIndex = chunkIndex
        updated.utf16Offset = resumeOffset
        updated.isFinished = finished
        document = updated
        onProgress?(updated)
    }

    private func activateAudio() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            return true
        } catch {
            errorMessage = "Couldn’t start audio: \(error.localizedDescription)"
            return false
        }
    }

    private func deactivateAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateNowPlaying() {
        guard let document else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: document.title,
            MPMediaItemPropertyArtist: "Folio Voice · Page \(currentPage) of \(document.pageCount)",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let actions: [(MPRemoteCommand, (SpeechPlayer) -> Void)] = [
            (center.playCommand, { $0.play() }),
            (center.pauseCommand, { $0.pause() }),
            (center.togglePlayPauseCommand, { $0.togglePlayback() }),
            (center.nextTrackCommand, { $0.skip(by: 1) }),
            (center.previousTrackCommand, { $0.skip(by: -1) })
        ]
        for (command, action) in actions {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    action(self)
                }
                return .success
            }
            remoteTargets.append((command, target))
        }
    }

    private func handleInterruption(type: UInt?, options: UInt) {
        if type == AVAudioSession.InterruptionType.began.rawValue {
            let wasPlaying = isPlaying
            pause()
            resumeAfterInterruption = wasPlaying
        } else if type == AVAudioSession.InterruptionType.ended.rawValue {
            let shouldResume = resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            resumeAfterInterruption = false
            if shouldResume { play() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            let range = NSRange(location: self.utteranceOffset + characterRange.location, length: characterRange.length)
            self.spokenRange = range
            self.resumeOffset = range.location
            self.checkpoint()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if synthesizer === self.previewSynthesizer {
                if !self.isPlaying && !self.previewSynthesizer.isSpeaking { self.deactivateAudio() }
                return
            }
            guard self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.resumeOffset = 0
            self.spokenRange = nil
            if self.chunkIndex + 1 < self.chunks.count {
                self.chunkIndex += 1
                self.speakCurrentChunk()
            } else {
                self.finished = true
                self.isPlaying = false
                self.isPaused = false
                self.checkpoint()
                self.updateNowPlaying()
                self.deactivateAudio()
            }
        }
    }
}
