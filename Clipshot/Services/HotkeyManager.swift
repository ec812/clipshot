import AppKit
import Carbon.HIToolbox
import Foundation

enum HotkeyError: LocalizedError, Equatable {
    case alreadyRegistered(HotkeyAction)
    case conflictWithSystem(HotkeyAction)
    case carbon(OSStatus)

    var errorDescription: String? {
        switch self {
        case .alreadyRegistered(let action):
            return "That shortcut is already used for “\(action.title)”."
        case .conflictWithSystem(let action):
            return "macOS or another app already uses that shortcut for “\(action.title)”."
        case .carbon(let status):
            return "Could not register the shortcut (error \(status))."
        }
    }
}

/// Global hotkeys through Carbon's RegisterEventHotKey.
/// This avoids the Input Monitoring TCC prompt that event taps would require.
@MainActor
final class HotkeyManager {
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var registered: [HotkeyAction: Hotkey] = [:]

    private let signature: OSType = 0x434C5053 // 'CLPS'

    init() {}

    deinit {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            clipshotHotkeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    func register(_ hotkey: Hotkey, for action: HotkeyAction, handler: @escaping () -> Void) throws {
        installEventHandlerIfNeeded()

        if let existing = registered[action] {
            if existing == hotkey {
                handlers[actionID(action)] = handler
                return
            }
            unregister(action)
        }

        if let conflicting = registered.first(where: { $0.key != action && $0.value == hotkey })?.key {
            throw HotkeyError.alreadyRegistered(conflicting)
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: actionID(action))
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            if status == OSStatus(-9878) { // eventHotKeyExistsErr
                throw HotkeyError.conflictWithSystem(action)
            }
            throw HotkeyError.carbon(status)
        }

        hotKeyRefs[actionID(action)] = ref
        handlers[actionID(action)] = handler
        registered[action] = hotkey
    }

    func unregister(_ action: HotkeyAction) {
        let id = actionID(action)
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: id)
        registered.removeValue(forKey: action)
    }

    func unregisterAll() {
        for action in HotkeyAction.allCases {
            unregister(action)
        }
    }

    private func actionID(_ action: HotkeyAction) -> UInt32 {
        UInt32((HotkeyAction.allCases.firstIndex(of: action) ?? 0) + 1)
    }

    fileprivate func handleHotKey(_ hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == signature else { return }
        let handler = handlers[hotKeyID.id]
        handler?()
    }
}

private func clipshotHotkeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

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
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.handleHotKey(hotKeyID)
    }
    return noErr
}
