import AppKit
import SwiftUI

// A recording target only; these tests never install a hotkey or post an event.
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var recordCardKey: ((UInt16) -> Void)?
    static func title(keyCode: UInt32, modifiers: UInt32) -> String { "Key \(keyCode)" }
}

@main struct CardNavigationProbe {
    static func main() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        precondition(old.cardNavigation.next == 48 && old.cardNavigation.previous == 50)
        precondition(old.clotheslinePositions.isEmpty)
        var preferences = old
        preferences.cardNavigation.set(53, for: .next)
        preferences.cardNavigation.set(56, for: .previous)
        preferences.clotheslinePositions["fixture.app"] = .init(x: 0.238721, y: 0.672314)
        let saved = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(Preferences.self, from: saved)
        precondition(restored == preferences, "New preferences lose precision on relaunch")
        let invalid = Data(#"{"cardNavigation":{"next":63,"previous":127},"clotheslinePositions":{"bad":{"x":2,"y":0}}}"#.utf8)
        let repaired = try JSONDecoder().decode(Preferences.self, from: invalid)
        precondition(repaired.cardNavigation == old.cardNavigation && repaired.clotheslinePositions.isEmpty)
        let duplicate = try JSONDecoder().decode(CardNavigationShortcuts.self, from: Data(#"{"next":50,"previous":50}"#.utf8))
        precondition(duplicate.next == 50 && duplicate.previous == 48)
        func event(_ key: UInt16, _ flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!
        }
        precondition(CardNavigationShortcuts.code(from: event(50, .shift)) == 50, "Tilde requires two-key shortcut")
        for flag: NSEvent.ModifierFlags in [.command, .control, .option] {
            precondition(CardNavigationShortcuts.code(from: event(0, flag)) == nil, "Modified shortcut steals unrelated input")
        }
        precondition(CardNavigationShortcuts.code(from: event(56, .init(rawValue: 0x20002), type: .flagsChanged)) == 56)
        precondition(CardNavigationShortcuts.code(from: event(60, .init(rawValue: 0x20004), type: .flagsChanged)) == 60)
        precondition(CardNavigationShortcuts.code(from: event(56, .init(rawValue: 0x20004), type: .flagsChanged)) == nil,
                     "Releasing left Shift while holding right Shift selects another card")
        precondition(CardNavigationShortcuts.code(from: event(57, .capsLock, type: .flagsChanged)) == 57)
        precondition(CardNavigationShortcuts.code(from: event(57, [], type: .flagsChanged)) == 57)
        for type in [0, 1, 2, 3, 6, 7, 16, 17, 18, 21, 22] {
            for state in [0x0a, 0x0b] {
                let media = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 8, data1: (type << 16) | (state << 8), data2: 0)!
                let expected: UInt16? = state == 0x0a && type != 6 ? UInt16(256 + type) : nil
                precondition(CardNavigationShortcuts.code(from: media) == expected, "Media key state/power exclusion is wrong")
            }
        }
        let unrelated = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 1, data1: 0, data2: 0)!
        precondition(CardNavigationShortcuts.code(from: unrelated) == nil, "Non-key system event treated as a physical key")
        precondition(CardNavigationShortcuts.label(50) == "~ / `")
        print("PASS: preference migration/round-trip, invalid-key repair, position persistence; tilde, Shift/Caps Lock, media keys and power/modifier exclusion; no input sent")
    }
}
