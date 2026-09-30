import AppKit
import Carbon.HIToolbox

struct Hotkey {
    let keyCode: Int
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    static let fullscreen = Hotkey(keyCode: kVK_ANSI_3, keyEquivalent: "3", modifiers: [.control, .option, .shift])
    static let region = Hotkey(keyCode: kVK_ANSI_4, keyEquivalent: "4", modifiers: [.control, .option, .shift])
    static let activeWindow = Hotkey(keyCode: kVK_ANSI_5, keyEquivalent: "5", modifiers: [.control, .option, .shift])
}

final class HotkeyManager {
    private static let signature: OSType = "SHRX".utf8.reduce(0) { ($0 << 8) + OSType($1) }

    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
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
            DispatchQueue.main.async { manager.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
    }

    deinit {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    @discardableResult
    func register(_ hotkey: Hotkey, action: @escaping () -> Void) -> Bool {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            hotkey.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRefs.append(ref)
        actions[id] = action
        return true
    }
}
