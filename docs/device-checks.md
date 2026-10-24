# iPhone verification

These checks require a simulator or physical iPhone. The macOS `swift test` suite does not substitute for them. Prefer a physical iPhone for voice downloads, interruptions, lock-screen audio, and connected headphones.

1. **Fresh install:** Launch with an empty library. Import a normal, multi-page PDF from Files. Confirm page count, clear import progress, readable text, and correct original-PDF display. Import from a cloud provider as well as local Files.
2. **Speech:** Play, pause mid-word, resume, and move backward and forward. Finish a short PDF and press Play again. Confirm that the highlighted text follows speech and switching documents immediately stops the previous one.
3. **Rate:** While speaking and while paused, select 0.5×, 1×, and 2×. Confirm audible differences and that the current reading position remains sensible. Extremely short phrases are not useful for judging speed.
4. **Voice/accent:** Compare two available voices. Preview one while playback is paused and while it is active. Confirm only one speech stream is audible. Download another voice in system settings and return to the app to confirm it appears.
5. **Saved place:** Listen long enough to cross several segments, pause, close the reader, and relaunch the app. Confirm the imported PDF, position, speed, and voice persist. Repeat with backgrounding during playback.
6. **Background:** While reading, lock the phone and use lock-screen Play/Pause and skip controls. Unlock and confirm the app's state matches. Verify a phone/audio interruption pauses correctly and resumption follows the system's interruption policy. Disconnect headphones and confirm playback pauses.
7. **OCR and errors:** Import a scanned PDF, a PDF with a blank page, a password-locked PDF, a corrupted file named `.pdf`, and a document beyond the stated size/page limits. Confirm useful errors, responsive UI, and no partial library item after a failed import.
8. **Library:** Import two documents, switch between them, remove the currently playing one, and relaunch. Confirm removed content stays removed and the original source file remains available in Files.
9. **Accessibility:** Check VoiceOver names for transport and speed controls. Try the largest text sizes, dark mode, landscape, and a compact iPhone display. Confirm the reader and voice list remain scrollable and controls remain reachable.

Record the iPhone/iOS version and installed voice names when reporting speech or OCR differences. These are system services and can vary across devices.
