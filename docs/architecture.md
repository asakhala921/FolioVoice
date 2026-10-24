# Architecture

The app targets iPhone on iOS 17 and later. Xcode compiles all app Swift files into a single application target. The Swift package also exposes `FolioVoice/Core` as `FolioCore` so the data and extraction layer can be tested on macOS without a simulator.

- **Core/ReadingDocument.swift:** Codable document, physical page numbers, reading position, and speech-segment models.
- **Core/TextChunker.swift:** Bounded segments preserve readable text and Unicode boundaries. A position combines the segment index and UTF-16 offset, matching speech delegate callbacks.
- **Core/DocumentRepository.swift:** An actor serializes manifest access. Imports run outside that actor so long OCR jobs do not delay progress saves. It coordinates security-scoped imports, retains a private PDF copy, extracts embedded text through PDFKit, and recognizes image-only pages with Vision. Atomic JSON writes preserve metadata and reading progress. Invalid manifests are surfaced instead of being overwritten.
- **Services/LibraryStore.swift:** Main-actor observable state bridges the repository to SwiftUI. It reports import progress, throttles position saves during continuous speech, and serializes manifest writes before removing local PDF copies.
- **Services/SpeechPlayer.swift:** Main-actor owner of speech playback, voice discovery, voice samples, and persisted voice/rate preferences. It configures a playback audio session and responds to remote controls, interruptions, and disconnected audio routes.
- **Views:** Library, reader, voice picker, original PDF viewer, and shared visual styling. The application owns one shared library and one shared speech player.

Speech is queued one segment at a time to keep skipping and setting changes responsive. The saved offset identifies the latest spoken word, so resuming may repeat a word instead of skipping unread text. Progress measures extracted text rather than elapsed audio time; no synthetic total-duration estimate is presented.

The Xcode project uses conventional explicit file references for compatibility. `scripts/generate-project.py` creates stable IDs from source paths, includes every Swift file under `FolioVoice`, and keeps `Info.plist` out of copied resources. It regenerates build settings too; intentional configuration changes should also be reflected in the generator. No remote package resolution is required.
