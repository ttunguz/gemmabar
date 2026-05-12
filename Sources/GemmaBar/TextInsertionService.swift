// TextInsertionService.swift - Insert dictation text into the focused app.
// Modeled after freeflow's proven paste approach (github.com/zachlatta/freeflow)

import AppKit
import Carbon
import Foundation

struct TextInsertionService: Sendable {
    static func captureTarget() -> TextInsertionTarget {
        let application = NSWorkspace.shared.frontmostApplication
        return TextInsertionTarget(
            processIdentifier: application?.processIdentifier,
            applicationName: application?.localizedName ?? "unknown"
        )
    }

    func insert(_ text: String, target: TextInsertionTarget) async throws -> String {
        // Write to pasteboard first
        NSPasteboard.general.clearContents()
        let clipboardWritten = NSPasteboard.general.setString(text, forType: .string)
        DictationLogger.log("Dictation clipboardWritten=\(clipboardWritten)")
        guard clipboardWritten else {
            throw DictationError.pasteboardWriteFailed
        }

        // Wait for clipboard to propagate AND for the F2 hotkey to be released.
        // Freeflow polls hasPressedShortcutInputs; we simply delay 250ms
        // which is enough for a human to release a toggle key.
        try await Task.sleep(nanoseconds: 250_000_000)

        // Post the paste event on the main thread
        await MainActor.run {
            postCmdV()
        }

        return "Cmd+V paste to \(target.applicationName)"
    }

    /// Post Cmd+V using a clean synthetic event (no physical keyboard state).
    /// Uses nil event source so the F2 hotkey state doesn't piggy-back.
    @MainActor
    private func postCmdV() {
        let vKeyCode: CGKeyCode = keyCodeForCharacter("v") ?? 9

        // Use nil source — synthetic event that does NOT inherit physical key state.
        // This prevents F2 (still held from the hotkey) from appearing in the event.
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        // Small delay between down/up to look like a real keypress
        Thread.sleep(forTimeInterval: 0.05)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)

        DictationLogger.log("Dictation posted clean Cmd+V (keyCode=\(vKeyCode))")
    }

    /// Resolve the actual keycode for a character on the current keyboard layout.
    /// Falls back to ANSI 'v' = 9 if lookup fails.
    private func keyCodeForCharacter(_ character: String) -> CGKeyCode? {
        guard let char = character.lowercased().utf16.first else { return nil }
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        return layoutData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> CGKeyCode? in
            guard let layout = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            for keyCode in UInt16(0)..<UInt16(128) {
                var chars = [UniChar](repeating: 0, count: 4)
                var charCount = 0
                var deadKeyState: UInt32 = 0
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, 4, &charCount, &chars
                )
                if status == noErr, charCount > 0, chars[0] == char {
                    return CGKeyCode(keyCode)
                }
            }
            return nil
        }
    }
}
