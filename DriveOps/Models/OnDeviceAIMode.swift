//
//  OnDeviceAIMode.swift
//  DriveOps
//
//  Replaces the old boolean "On-Device AI" toggle. Apple's FoundationModels
//  framework exposes two models behind the same LanguageModelSession API:
//  SystemLanguageModel (on-device, always available offline, small context)
//  and PrivateCloudComputeLanguageModel (Apple's server-side model — larger
//  context, needs network, subject to a daily per-user quota Apple doesn't
//  publish a fixed number for). Letting the user pick between them — or turn
//  the Mechanic feature off entirely — needs three states, not two.
//

import Foundation

enum OnDeviceAIMode: String, CaseIterable, Identifiable {
    case off
    case systemModel
    case privateCloudCompute

    var id: String { rawValue }

    /// The modes offered in the picker. `.privateCloudCompute` is excluded
    /// here — not deleted from the enum — because it needs
    /// `com.apple.developer.private-cloud-compute`, a *managed* entitlement
    /// Apple grants on request (see "Accessing Private Cloud Compute" in
    /// Apple's docs), which this app doesn't have yet. Calling
    /// `PrivateCloudComputeLanguageModel()` without it doesn't fail
    /// gracefully — it hits an internal `assert` inside FoundationModels
    /// and crashes the process outright (confirmed via on-device crash
    /// report: `_assertionFailure` inside FoundationModels, not a catchable
    /// `LanguageModelSession`/`PrivateCloudComputeLanguageModel` error).
    /// Re-enable this case in `selectableCases` once the entitlement is
    /// approved and added to `DriveOps.entitlements`.
    static var selectableCases: [OnDeviceAIMode] { [.off, .systemModel] }

    var displayName: String {
        switch self {
        case .off:                 return "Off"
        case .systemModel:         return "On-Device"
        case .privateCloudCompute: return "Cloud"
        }
    }

    var footerDescription: String {
        switch self {
        case .off:
            return "The Mechanic section is hidden. Use \"Ask…\" to open an external provider instead."
        case .systemModel:
            return "Explains codes entirely on-device — works offline, no data leaves the phone."
        case .privateCloudCompute:
            return "Uses Apple's server-side model for longer, more capable explanations. Requires a network connection and an Apple Intelligence–eligible device; Apple applies a daily usage limit per user."
        }
    }
}

extension OnDeviceAIMode {
    private static let storageKey = "onDeviceAIMode"
    // The feature shipped as a plain on/off Toggle before Private Cloud
    // Compute support existed — this is that Bool's old @AppStorage key.
    // Read once, on first launch after the update, so someone who had
    // on-device AI enabled doesn't silently lose it just because the
    // setting is now a three-way picker instead of a switch.
    private static let legacyEnabledKey = "onDeviceAIEnabled"

    /// The mode to use as `@AppStorage`'s default, migrating the old
    /// boolean toggle's value the first time this runs post-update. Safe to
    /// call repeatedly — once `storageKey` has any value, that value wins
    /// and the legacy key is never consulted again.
    static func loadInitial() -> OnDeviceAIMode {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: storageKey), let mode = OnDeviceAIMode(rawValue: saved) {
            // Defensive downgrade: if this device already persisted
            // .privateCloudCompute (e.g. selected before the crash above was
            // diagnosed and the option pulled from the picker), never hand
            // it back out — the caller can't act on it safely. Falls back to
            // the on-device model rather than silently turning AI off, since
            // that best matches what someone who picked *some* AI mode wanted.
            return mode == .privateCloudCompute ? .systemModel : mode
        }
        if defaults.object(forKey: legacyEnabledKey) != nil {
            return defaults.bool(forKey: legacyEnabledKey) ? .systemModel : .off
        }
        return .systemModel
    }
}
