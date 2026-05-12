// GemmaBarApp.swift - GemmaBar menu bar app entry point
// Uses SwiftUI MenuBarExtra for the visible menu bar control.

import AppKit
import SwiftUI

@main
struct GemmaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var audioManager = AudioDeviceManager.shared

    var body: some Scene {
        MenuBarExtra {
            Text(appDelegate.menuStatusTitle)
            Text(appDelegate.menuModelTitle)
            Text(appDelegate.menuPortTitle)
            Text(appDelegate.dictationStatusTitle)

            Divider()

            Button(appDelegate.dictationActionTitle) {
                appDelegate.toggleDictation()
            }
            .keyboardShortcut("d")

            Divider()

            Button("Load Dictation Server") {
                appDelegate.loadDictation()
            }
            .keyboardShortcut("1")

            Divider()

            Text("Microphone: \(audioManager.selectedDevice?.name ?? "System Default")")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(audioManager.inputDevices) { device in
                Button {
                    audioManager.selectedDevice = device
                } label: {
                    HStack {
                        Text(device.name)
                        Spacer()
                        if audioManager.selectedDevice?.id == device.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button("Restart Server") {
                appDelegate.restartServer()
            }
            .keyboardShortcut("r")

            Button("Unload Model") {
                appDelegate.unloadModel()
            }
            .keyboardShortcut("u")

            Button("Telemetry...") {
                appDelegate.showTelemetry()
            }
            .keyboardShortcut("t")

            Button("Custom Vocabulary...") {
                appDelegate.showCustomVocabulary()
            }
            .keyboardShortcut("v")

            Button(appDelegate.dictationShortcutTitle) {
                appDelegate.showDictationShortcut()
            }

            Divider()

            Button("Quit GemmaBar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Label("GemmaBar", systemImage: "megaphone.fill")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            EmptyView()
        }
    }
}
