//
//  ComposeResult.swift
//  Scan
//
//  The value the Generate tab's "describe the code" box produces, whichever
//  engine produced it. Shared by the on-device model (Assistant.swift) and
//  the rule-based fallback (HeuristicExplainer.swift) so the form UI has one
//  thing to apply, and so the fallback can be tested without the language
//  model in the picture.
//

import Foundation

// MARK: - Compose result

/// Which form the composed values belong to. The Generate tab builds text,
/// URL, Wi-Fi and contact codes; the other kinds are kept so the vocabulary
/// matches the Android port, and neither engine produces them today.
enum ComposeKind: String {
    case text, url, wifi, contact, email, phone, payment, product
}

/// Fields + literal text the Generate form should apply.
///
/// `values` keys are always lower-case. The vocabulary both engines use:
/// - wifi: `ssid`, `password`, `security` (as written, e.g. "WPA3"), `hidden` ("true")
/// - contact: `name`, `phone`, `email`, `org`
/// - url / text: no values; the link or text is in `text`
struct ComposeResult: Equatable {
    enum Source: Equatable { case onDeviceModel, builtIn }

    var kind: ComposeKind
    var values: [String: String]
    var text: String
    var source: Source

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && values.isEmpty
    }

    func value(_ key: String) -> String? {
        let v = values[key.lowercased()]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }

    /// The `T:` tag of a `WIFI:` payload for the requested security, so the
    /// form can pick its security option without re-parsing free text:
    /// "WPA", "SAE" (WPA3), "WEP" or "nopass". Nil when the request did not
    /// say — the form keeps its own default then.
    var wifiSecurityTag: String? {
        guard let security = value("security")?.uppercased() else { return nil }
        switch security {
        case "WPA", "WPA2", "WPA/WPA2", "WPA2/WPA3":  return "WPA"
        case "WPA3", "SAE":                          return "SAE"
        case "WEP":                                  return "WEP"
        case "NOPASS", "NOPEN", "NONE", "OPEN":      return "nopass"
        default:                                     return nil
        }
    }

    /// Whether a composed Wi-Fi network was described as hidden.
    var isHiddenNetwork: Bool {
        value("hidden")?.lowercased() == "true"
    }
}
