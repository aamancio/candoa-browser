import AppKit

/// Translates between Talos's stored shortcut strings ("Shift-Command-E",
/// the form `ShortcutDefinition` persists and the Shortcuts pane records)
/// and the activation key plus modifier flags a `WKWebExtension.Command`
/// carries. An extension's manifest suggests a key; the person may rebind
/// or remove it in Settings; WebKit matches key events against whatever
/// the command holds. This is the one place the two spellings meet.
enum WebExtensionShortcut {
    /// Stored for a command whose shortcut the person removed; the same
    /// marker `ShortcutDefinition` uses for the browser's own keys.
    static let removedValue = "none"

    /// Modifier names in the order the stored string lists them.
    private static let modifierNames: [(name: String, flag: NSEvent.ModifierFlags)] = [
        ("Control", .control),
        ("Option", .option),
        ("Shift", .shift),
        ("Command", .command),
    ]

    private static func functionKey(_ code: Int) -> String {
        String(UnicodeScalar(UInt32(code)).map(Character.init) ?? Character(" "))
    }

    /// Keys that a stored string names rather than spells.
    private static let namedKeys: [(name: String, key: String)] = {
        var keys: [(name: String, key: String)] = [
            ("Tab", "\t"),
            ("Space", " "),
            ("Left", functionKey(NSLeftArrowFunctionKey)),
            ("Right", functionKey(NSRightArrowFunctionKey)),
            ("Up", functionKey(NSUpArrowFunctionKey)),
            ("Down", functionKey(NSDownArrowFunctionKey)),
            ("Home", functionKey(NSHomeFunctionKey)),
            ("End", functionKey(NSEndFunctionKey)),
            ("PageUp", functionKey(NSPageUpFunctionKey)),
            ("PageDown", functionKey(NSPageDownFunctionKey)),
            ("Insert", functionKey(NSInsertFunctionKey)),
            ("Delete", functionKey(NSDeleteFunctionKey)),
        ]
        for number in 1...12 {
            keys.append(("F\(number)", functionKey(NSF1FunctionKey + number - 1)))
        }
        return keys
    }()

    /// The stored string for a command's current key, or "None" when it
    /// has no key.
    static func string(activationKey: String?, modifierFlags: NSEvent.ModifierFlags) -> String {
        guard let activationKey, !activationKey.isEmpty else { return "None" }
        var parts = modifierNames.filter { modifierFlags.contains($0.flag) }.map(\.name)
        if let named = namedKeys.first(where: { $0.key == activationKey }) {
            parts.append(named.name)
        } else {
            parts.append(activationKey.uppercased())
        }
        return parts.joined(separator: "-")
    }

    /// The key and modifiers a stored string names. "None", the removed
    /// marker, and anything unreadable give a nil key, which clears the
    /// command's shortcut.
    static func components(from string: String) -> (activationKey: String?, modifierFlags: NSEvent.ModifierFlags) {
        guard !string.isEmpty, string != "None", string != removedValue else { return (nil, []) }

        var pieces = string.components(separatedBy: "-")
        // A literal "-" key ("Command--") splits into trailing empty
        // components, the same way ShortcutDefinition handles it.
        if pieces.last == "" {
            pieces.removeAll { $0.isEmpty }
            pieces.append("-")
        }
        guard let keyPiece = pieces.popLast(), !keyPiece.isEmpty else { return (nil, []) }

        var flags: NSEvent.ModifierFlags = []
        for piece in pieces {
            guard let modifier = modifierNames.first(where: { $0.name == piece }) else { return (nil, []) }
            flags.insert(modifier.flag)
        }
        // A bare key would fire while the person types; a shortcut always
        // carries a modifier, as the capture view already insists.
        guard !flags.isEmpty else { return (nil, []) }

        if let named = namedKeys.first(where: { $0.name == keyPiece }) {
            return (named.key, flags)
        }
        guard keyPiece.count == 1 else { return (nil, []) }
        return (keyPiece.lowercased(), flags)
    }
}
