// GemmaBarApp.swift - GemmaBar menu bar app entry point
// Uses SwiftUI MenuBarExtra for the visible menu bar control.

import AppKit
import SwiftUI

@main
struct GemmaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var audioManager = AudioDeviceManager.shared
    @State private var waveformFrame = 0
    @State private var waveformTimer: Timer?

    /// SF Symbols that cycle during recording to create a subtle waveform animation.
    private static let waveformIcons = [
        "waveform",
        "waveform.badge.mic",
        "waveform",
        "waveform.badge.mic"
    ]

    private var menuBarIcon: String {
        guard let dictation = appDelegate.dictationController else {
            return "megaphone.fill"
        }
        switch dictation.state {
        case .recording:
            return Self.waveformIcons[waveformFrame % Self.waveformIcons.count]
        case .transcribing:
            return "text.bubble"
        case .cleaning:
            return "sparkles"
        case .error:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "megaphone.fill"
        }
    }

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

            Divider()

            Button("Quit GemmaBar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: appDelegate.dictationController?.state ?? .idle) { _, newState in
            if newState.isRecording {
                startWaveformAnimation()
            } else {
                stopWaveformAnimation()
            }
        }

        Settings {
            EmptyView()
        }
    }

    private func startWaveformAnimation() {
        waveformFrame = 0
        waveformTimer?.invalidate()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                waveformFrame += 1
            }
        }
    }

    private func stopWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = nil
        waveformFrame = 0
    }
}
