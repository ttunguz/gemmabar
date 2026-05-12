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
    private var dictationShortcutWindow: NSWindow?
    private var dictationShortcutController: DictationShortcutViewController?
    private var cancellables = Set<AnyCancellable>()
    private var dictationHotKeyRef: EventHotKeyRef?
    private var dictationHotKeyHandlerRef: EventHandlerRef?
    private var dictationShortcut = DictationShortcut.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        installDictationHotkeyHandler()
        registerDictationHotkey()
        requestAccessibilityPermissionForPaste()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let dictationHotKeyRef {
            UnregisterEventHotKey(dictationHotKeyRef)
        }
        if let dictationHotKeyHandlerRef {
            RemoveEventHandler(dictationHotKeyHandlerRef)
        }
        serverController.stopServer()
    }

    private func installDictationHotkeyHandler() {
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
            &dictationHotKeyHandlerRef
        )
    }

    private func registerDictationHotkey() {
        if let dictationHotKeyRef {
            UnregisterEventHotKey(dictationHotKeyRef)
            self.dictationHotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: 0x47424454, id: 1) // "GBDT"
        let status = RegisterEventHotKey(
            dictationShortcut.keyCode,
            dictationShortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &dictationHotKeyRef
        )
        DictationLogger.log("Dictation hotkey \(dictationShortcut.displayName) registration status=\(status)")
    }

    private func requestAccessibilityPermissionForPaste() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DictationController.log("Accessibility trusted for paste=\(trusted)")
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

    @objc func showDictationShortcut() {
        DictationLogger.log("Dictation shortcut editor requested")
        if let dictationShortcutWindow {
            DictationLogger.log("Showing existing dictation shortcut window")
            dictationShortcutWindow.makeKeyAndOrderFront(nil)
            dictationShortcutWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictation Shortcut"
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false

        let controller = DictationShortcutViewController(
            shortcut: dictationShortcut,
            onCancel: { [weak self] in
                self?.dictationShortcutWindow?.close()
            },
            onSave: { [weak self] shortcut in
                guard let self else { return }
                self.dictationShortcut = shortcut
                shortcut.save()
                self.registerDictationHotkey()
                self.objectWillChange.send()
                DictationLogger.log("Dictation shortcut saved: \(shortcut.displayName)")
                self.dictationShortcutWindow?.close()
            }
        )
        window.contentViewController = controller

        dictationShortcutWindow = window
        dictationShortcutController = controller
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        DictationLogger.log("Dictation shortcut window opened")
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

    var dictationShortcutTitle: String {
        "Dictation Shortcut: \(dictationShortcut.displayName)"
    }
}

extension AppDelegate: ServerControllerDelegate {
    func serverStateDidChange() {}
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if window === customVocabularyWindow {
            customVocabularyWindow = nil
        }
        if window === dictationShortcutWindow {
            dictationShortcutWindow = nil
            dictationShortcutController = nil
        }
    }
}
