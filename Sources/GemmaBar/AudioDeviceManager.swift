// AudioDeviceManager.swift — Discover & select macOS audio input devices
// Uses CoreAudio to enumerate input devices and persist the selection.

import Foundation
import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    private let selectedDeviceKey = "com.gemmabar.selectedAudioDeviceUID"

    @Published var selectedDevice: AudioDevice? {
        didSet {
            UserDefaults.standard.set(selectedDevice?.uid, forKey: selectedDeviceKey)
        }
    }

    init() {
        // Auto-select Rode on first launch if no preference saved
        if UserDefaults.standard.object(forKey: selectedDeviceKey) == nil {
            selectedDevice = findRodeDevice()
        }
    }

    /// All currently available input devices
    var inputDevices: [AudioDevice] {
        var devices = [AudioDevice]()

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return devices }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return devices }

        for deviceID in deviceIDs {
            if isInputDevice(deviceID) {
                if let name = getDeviceName(deviceID), let uid = getDeviceUID(deviceID) {
                    devices.append(AudioDevice(id: deviceID, name: name, uid: uid))
                }
            }
        }

        // Restore saved selection if it still exists
        if selectedDevice == nil,
           let savedUID = UserDefaults.standard.string(forKey: selectedDeviceKey) {
            selectedDevice = devices.first { $0.uid == savedUID }
        }

        return devices
    }

    func findRodeDevice() -> AudioDevice? {
        inputDevices.first { $0.name.lowercased().contains("rode") }
    }

    // MARK: — CoreAudio helpers

    private func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return false }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferList.deallocate() }

        var dataSizeVar = dataSize
        let status2 = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSizeVar, bufferList)
        guard status2 == noErr else { return false }

        return bufferList.pointee.mNumberBuffers > 0
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        guard status == noErr else { return nil }

        return name as String
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)
        guard status == noErr else { return nil }

        return uid as String
    }
}
