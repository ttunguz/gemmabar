// AppDelegate.swift - GemmaBar application delegate
// Owns the server lifecycle. The visible menu bar item is defined by MenuBarExtra.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private nonisolated(unsafe) static weak var hotKeyOwner: AppDelegate?

    var serverController: ServerController!
    var dictationController: DictationController!
    private var customVocabularyWindow: NSWindow?
    private var pasteTestWindow: NSWindow?
    private var pasteTestTextView: NSTextView?
    private var cancellables = Set<AnyCancellable>()
    private var f2HotKeyRef: EventHotKeyRef?
    private var f2HotKeyHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["GEMMABAR_PASTE_SELF_TEST"] == "1" {
            runPasteSelfTest()
            return
        }

        NSApp.setActivationPolicy(.accessory)

        serverController = ServerController()
        serverController.delegate = self
        dictationController = DictationController(serverController: serverController)
        serverController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        dictationController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        Task {
            await serverController.loadDefaultModel()
        }

        installF2DictationHotkey()
        requestAccessibilityPermissionForPaste()
        requestInputMonitoringPermissionForPaste()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let f2HotKeyRef {
            UnregisterEventHotKey(f2HotKeyRef)
        }
        if let f2HotKeyHandlerRef {
            RemoveEventHandler(f2HotKeyHandlerRef)
        }
        serverController?.stopServer()
    }

    private func installF2DictationHotkey() {
        Self.hotKeyOwner = self

        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.id == 1 else { return noErr }

            Task { @MainActor in
                AppDelegate.hotKeyOwner?.toggleDictation()
            }
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &f2HotKeyHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: 0x47424632, id: 1) // "GBF2"
        RegisterEventHotKey(
            UInt32(kVK_F2),
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &f2HotKeyRef
        )
    }

    private func requestAccessibilityPermissionForPaste() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DictationController.log("Accessibility trusted for paste=\(trusted)")
    }

    private func requestInputMonitoringPermissionForPaste() {
        let trustedBefore = CGPreflightListenEventAccess()
        if !trustedBefore {
            let requested = CGRequestListenEventAccess()
            DictationController.log("Input Monitoring requested=\(requested)")
        }
        let trustedAfter = CGPreflightListenEventAccess()
        DictationController.log("Input Monitoring trusted for paste=\(trustedAfter)")
    }

    private func runPasteSelfTest() {
        NSApp.setActivationPolicy(.regular)
        installPasteSelfTestMenu()

        let environment = ProcessInfo.processInfo.environment
        let marker = environment["GEMMABAR_PASTE_MARKER"] ?? "GemmaBar paste self-test"
        let resultPath = environment["GEMMABAR_PASTE_RESULT"] ?? "/tmp/gemmabar-paste-self-test-result"

        let window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 640, height: 240),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GemmaBar Paste Self-Test"

        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 640, height: 240))
        scrollView.autoresizingMask = [.width, .height]
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 18)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        window.contentView = scrollView

        pasteTestWindow = window
        pasteTestTextView = textView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        window.makeFirstResponder(textView)

        NSPasteboard.general.clearContents()
        let clipboardWritten = NSPasteboard.general.setString(marker, forType: .string)
        DictationController.log("Paste self-test clipboardWritten=\(clipboardWritten); markerChars=\(marker.count)")

        // Wait longer for window to fully initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // Verify permissions before paste
            let axTrusted = AXIsProcessTrusted()
            let inputTrusted = CGPreflightListenEventAccess()
            DictationController.log("Paste self-test permissions: AX=\(axTrusted); InputMonitoring=\(inputTrusted)")

            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            self?.pasteTestWindow?.makeKeyAndOrderFront(nil)
            self?.pasteTestWindow?.makeFirstResponder(self?.pasteTestTextView)
            let target = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
            let firstResponder = String(describing: self?.pasteTestWindow?.firstResponder)
            DictationController.log("Paste self-test before paste target=\(target); firstResponder=\(firstResponder)")

            // Try CGEvent-based paste first
            DictationController.pasteClipboardIntoFrontmostApp()
        }

        // Check if CGEvent paste worked after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            let cgEventResult = self?.pasteTestTextView?.string ?? ""
            DictationController.log("Paste self-test CGEvent result: chars=\(cgEventResult.count)")

            // If CGEvent didn't work, try NSText.paste as fallback
            if cgEventResult.isEmpty {
                DictationController.log("Paste self-test: CGEvent paste failed, trying NSText.paste fallback")
                self?.pasteTestTextView?.paste(nil)
            }
        }

        // Final check
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            let result = self?.pasteTestTextView?.string ?? ""
            try? result.write(toFile: resultPath, atomically: true, encoding: .utf8)
            let cgEventWorked = result.contains(marker) && result.count == marker.count
            DictationController.log("Paste self-test resultChars=\(result.count); matched=\(result.contains(marker)); cgEventWorked=\(cgEventWorked)")
            NSApp.terminate(nil)
        }
    }

    private func installPasteSelfTestMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: "Quit GemmaBar",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            NSMenuItem(
                title: "Paste",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            )
        )
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

extension AppDelegate {
    @objc func loadDictation() {
        Task {
            await serverController.loadModel(.dictation)
        }
    }

    @objc func restartServer() {
        Task {
            await serverController.restartServer()
        }
    }

    @objc func unloadModel() {
        serverController.unloadModel()
    }

    @objc func toggleDictation() {
        dictationController.toggleRecording()
    }

    @objc func showTelemetry() {
        let port = serverController?.port ?? 8087
        let url = URL(string: "http://localhost:\(port)/health")!
        NSWorkspace.shared.open(url)
    }

    @objc func showCustomVocabulary() {
        if let customVocabularyWindow {
            customVocabularyWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Custom Vocabulary"
        window.center()
        window.minSize = NSSize(width: 420, height: 280)
        window.isReleasedWhenClosed = false

        window.contentView = NSHostingView(rootView: CustomVocabularyView(
            onCancel: { [weak self] in
                self?.customVocabularyWindow?.close()
            },
            onSave: { [weak self] in
                self?.customVocabularyWindow?.close()
            }
        ))

        customVocabularyWindow = window
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var menuStatusTitle: String {
        serverController?.state.menuTitle ?? "○ Starting"
    }

    var menuModelTitle: String {
        "Model: \(serverController?.currentModelName ?? "—")"
    }

    var menuPortTitle: String {
        "Port: \(serverController?.port ?? 8087)"
    }

    var dictationStatusTitle: String {
        dictationController?.state.menuTitle ?? "Dictation: Starting"
    }

    var dictationActionTitle: String {
        if dictationController?.state.isRecording == true {
            return "Stop Dictation"
        }
        return "Start Dictation"
    }
}

extension AppDelegate: ServerControllerDelegate {
    func serverStateDidChange() {}
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === customVocabularyWindow else { return }
        customVocabularyWindow = nil
    }
}
