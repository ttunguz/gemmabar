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
    private var cancellables = Set<AnyCancellable>()
    private var f2HotKeyRef: EventHotKeyRef?
    private var f2HotKeyHandlerRef: EventHandlerRef?

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

        installF2DictationHotkey()
        requestAccessibilityPermissionForPaste()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let f2HotKeyRef {
            UnregisterEventHotKey(f2HotKeyRef)
        }
        if let f2HotKeyHandlerRef {
            RemoveEventHandler(f2HotKeyHandlerRef)
        }
        serverController.stopServer()
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
