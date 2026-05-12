// DictationShortcut.swift - Persistent global hotkey configuration for dictation.

import Carbon.HIToolbox
import AppKit

struct DictationShortcut: Equatable {
    static let defaultsKeyCodeKey = "dictationShortcut.keyCode"
    static let defaultsModifiersKey = "dictationShortcut.modifiers"
    static let defaultShortcut = DictationShortcut(keyCode: UInt32(kVK_F2), modifiers: 0)

    let keyCode: UInt32
    let modifiers: UInt32

    var displayName: String {
        let prefix = [
            (modifiers & UInt32(cmdKey)) != 0 ? "⌘" : "",
            (modifiers & UInt32(optionKey)) != 0 ? "⌥" : "",
            (modifiers & UInt32(controlKey)) != 0 ? "⌃" : "",
            (modifiers & UInt32(shiftKey)) != 0 ? "⇧" : ""
        ].joined()
        return prefix + Self.keyName(for: keyCode)
    }

    var isBareNonFunctionKey: Bool {
        modifiers == 0 && !Self.functionKeyCodes.contains(keyCode)
    }

    private static let functionKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1),
        UInt32(kVK_F2),
        UInt32(kVK_F3),
        UInt32(kVK_F4),
        UInt32(kVK_F5),
        UInt32(kVK_F6),
        UInt32(kVK_F7),
        UInt32(kVK_F8),
        UInt32(kVK_F9),
        UInt32(kVK_F10),
        UInt32(kVK_F11),
        UInt32(kVK_F12),
        UInt32(kVK_F13),
        UInt32(kVK_F14),
        UInt32(kVK_F15),
        UInt32(kVK_F16),
        UInt32(kVK_F17),
        UInt32(kVK_F18),
        UInt32(kVK_F19),
        UInt32(kVK_F20)
    ]

    static func load() -> DictationShortcut {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: defaultsKeyCodeKey) != nil else {
            return defaultShortcut
        }
        return DictationShortcut(
            keyCode: UInt32(defaults.integer(forKey: defaultsKeyCodeKey)),
            modifiers: UInt32(defaults.integer(forKey: defaultsModifiersKey))
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: Self.defaultsKeyCodeKey)
        defaults.set(Int(modifiers), forKey: Self.defaultsModifiersKey)
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_Space: return "Space"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "Key \(keyCode)"
        }
    }
}

final class DictationShortcutViewController: NSViewController {
    private var shortcut: DictationShortcut
    private let onSave: (DictationShortcut) -> Void
    private let onCancel: () -> Void

    private let titleLabel = NSTextField(labelWithString: "Dictation Shortcut")
    private let helpLabel = NSTextField(wrappingLabelWithString: "Click the field, then press the shortcut you want to use for starting and stopping dictation.")
    private let shortcutField = ShortcutCaptureField()
    private let validationLabel = NSTextField(labelWithString: "")
    private let resetButton = NSButton(title: "Reset to F2", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    init(
        shortcut: DictationShortcut,
        onCancel: @escaping () -> Void,
        onSave: @escaping (DictationShortcut) -> Void
    ) {
        self.shortcut = shortcut
        self.onCancel = onCancel
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 230))
        view.translatesAutoresizingMaskIntoConstraints = false
        configureViews()
        layoutViews()
        updateShortcutDisplay()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(shortcutField)
    }

    private func configureViews() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.font = .systemFont(ofSize: 13)
        shortcutField.onShortcut = { [weak self] shortcut in
            self?.shortcut = shortcut
            self?.updateShortcutDisplay()
            DictationLogger.log("Dictation shortcut captured: \(shortcut.displayName)")
        }

        validationLabel.font = .systemFont(ofSize: 12)
        validationLabel.textColor = .secondaryLabelColor

        resetButton.target = self
        resetButton.action = #selector(resetShortcut)
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"

        [titleLabel, helpLabel, shortcutField, validationLabel, resetButton, cancelButton, saveButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
    }

    private func layoutViews() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            helpLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            helpLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            helpLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            shortcutField.topAnchor.constraint(equalTo: helpLabel.bottomAnchor, constant: 14),
            shortcutField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            shortcutField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            shortcutField.heightAnchor.constraint(equalToConstant: 74),

            validationLabel.topAnchor.constraint(equalTo: shortcutField.bottomAnchor, constant: 8),
            validationLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            validationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            resetButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            resetButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor)
        ])
    }

    private func updateShortcutDisplay() {
        shortcutField.shortcut = shortcut
        if shortcut.isBareNonFunctionKey {
            validationLabel.stringValue = "Use a modifier with letter, number, arrow, or punctuation keys."
            validationLabel.textColor = .systemRed
            saveButton.isEnabled = false
        } else {
            validationLabel.stringValue = "Function keys can be used without modifiers."
            validationLabel.textColor = .secondaryLabelColor
            saveButton.isEnabled = true
        }
    }

    @objc private func resetShortcut() {
        shortcut = .defaultShortcut
        updateShortcutDisplay()
    }

    @objc private func cancel() {
        onCancel()
    }

    @objc private func save() {
        guard !shortcut.isBareNonFunctionKey else { return }
        onSave(shortcut)
    }
}

private final class ShortcutCaptureField: NSView {
    var shortcut: DictationShortcut = .defaultShortcut {
        didSet { label.stringValue = shortcut.displayName }
    }
    var onShortcut: ((DictationShortcut) -> Void)?

    private let label = NSTextField(labelWithString: DictationShortcut.defaultShortcut.displayName)

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 8, dy: 8)
    }

    override func becomeFirstResponder() -> Bool {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return true
    }

    override func resignFirstResponder() -> Bool {
        layer?.borderColor = NSColor.separatorColor.cgColor
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.carbonHotKeyModifiers
        onShortcut?(DictationShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
    }
}

private extension NSEvent.ModifierFlags {
    var carbonHotKeyModifiers: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
