# Folio Voice

A native iPhone app that turns PDFs into something you can listen to. Built with SwiftUI, PDFKit, Vision, and Apple's speech synthesis, with no third-party dependencies or accounts.

## Open and run

1. Install full **Xcode 16 or later** on your Mac. Command Line Tools alone cannot build an iPhone app.
2. Open **`FolioVoice.xcodeproj`** and select the **FolioVoice** scheme.
3. Choose an iPhone simulator running **iOS 17 or later**, then press **⌘R**.
4. For your own iPhone, connect it, select it as the destination, and choose your Apple development team under **FolioVoice → Signing & Capabilities**. Use a unique bundle identifier if Xcode requests one. Enable Developer Mode on the phone if prompted.

The project has no team or signing credentials committed. There is no App Store deployment step required to run it from Xcode on your own device.

## Listen to a PDF

- Tap **Import a PDF** and choose a document from Files, including a connected cloud provider.
- Open it from your library and press Play. The reader follows the spoken text and saves your place.
- Adjust the reading speed from **0.5× to 2×**. These values map onto Apple's speech-rate controls; exact timing varies by voice and text.
- Choose a voice and accent from the voices iOS makes available. Listen to a voice sample before choosing. To expand the selection, download additional system voices in your iPhone's Accessibility voice settings, then return to the app.
- Move between reading segments, inspect the original PDF, and resume from your saved place. Playback supports background audio and lock-screen controls.

The accent picker uses actual system voices; available accents and voice quality depend on your device and installed voice assets. Choosing a language's voice does not translate the document.

## Files and limitations

PDF copies, extracted text, and reading positions live in the app's local Application Support folder. Speech and scanned-page recognition run through Apple's on-device frameworks. Folio Voice has no app server, analytics SDK, or document upload service. Importing an iCloud/other cloud file or downloading a voice can require a network connection. Normal device backups may include the local library.

Text PDFs are read directly. Pages with no embedded text use OCR. Multi-column documents, tables, mathematics, headers, and poor-quality scans can produce an imperfect reading order or recognition result. Pages with some embedded text do not receive a second OCR pass for additional text inside images. Password-locked documents must be unlocked before import. Imports are limited to 100 MB, 1,000 pages, and 10 million extracted UTF-16 code units per document.

Removing a document deletes the app's copy and saved text; it leaves the original imported file alone. Uninstalling the app removes its local library.

## Development and verification

The Xcode project is already generated. After adding or removing Swift source files, regenerate its source list:

```sh
python3 scripts/generate-project.py
```

Run the standalone Core verification, including real generated text and scanned PDFs, OCR, Unicode text splitting, saved positions, cancellation, and file cleanup. This works with Command Line Tools:

```sh
swift run FolioCoreSmokeCheck
```

Run the XCTest suite with full Xcode selected:

```sh
swift test
```

With full Xcode selected, build without device signing:

```sh
xcodebuild -project FolioVoice.xcodeproj \
  -scheme FolioVoice \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO build
```

Verified in the original development environment: **22 standalone Core checks passed**, and the complete app compiled and linked against the Mac Catalyst SDK without API shims. Project/plist and asset references were validated. The local Command Line Tools installation does not include XCTest, an iOS SDK, or a simulator.

Core checks do not exercise iPhone speech, audio sessions, SwiftUI layouts, or lock-screen behavior. Those still require the Xcode build and the [device checks](docs/device-checks.md). Mac Catalyst compilation is not an iOS build or a device test.

The original app icons can be regenerated on macOS with `swift scripts/draw-icon.swift`. See [architecture](docs/architecture.md) for implementation boundaries.

Apple framework references: [speech synthesis](https://developer.apple.com/documentation/avfoundation/speech-synthesis), [speech rate](https://developer.apple.com/documentation/avfaudio/avspeechutterance/rate), and [text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).
