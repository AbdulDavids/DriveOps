//
//  SettingsView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

// MARK: - Changelog

private struct ChangelogEntry: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let items: [String]
}

private let changelog: [ChangelogEntry] = [
    ChangelogEntry(
        version: "0.3.0",
        date: "Sep 2026",
        items: [
            "BLE device picker — choose which adapter to connect to instead of auto-connecting to the first one found",
            "Support for BLE OBD2 adapters with unrecognised GATT UUIDs (property-based fallback)",
            "Fixed live data batches failing on vehicles that don't accept large multi-PID requests",
            "Selectable live data PIDs from the dashboard — choose exactly which sensors to poll",
            "VIN decoding — manufacturer, model year, and origin shown in the Vehicle card",
            "AI Mechanic explanations now include decoded vehicle info for more relevant answers",
            "Apple Intelligence model picker in Settings (On-Device / Off)",
            "Fixed a crash opening Diagnostics after selecting the (since removed) Cloud AI option",
        ]
    ),
    ChangelogEntry(
        version: "0.2.7",
        date: "Apr 2026",
        items: [
            "Metric history graphs with sparklines on dashboard",
            "Tap any metric to view full chart with min/max/current",
            "Apple Intelligence on-device code explanations (Mechanic)",
            "Realistic simulated driving cycle in demo mode",
            "More DTC codes in demo mode",
            "AI chat provider picker — ChatGPT, Claude, Gemini, Mistral",
            "On-device AI toggle and model selector in Settings",
        ]
    ),
    ChangelogEntry(
        version: "0.2.6",
        date: "Apr 2026",
        items: [
            "Welcome flow on first launch",
            "Demo mode prompt on dashboard when disconnected",
            "Version shows build number in Settings"
        ]
    ),
    ChangelogEntry(
        version: "0.2.5",
        date: "Apr 2026",
        items: [
            "New Diagnostics tab — read & clear DTCs",
            "Trouble code detail view with descriptions",
            "Dashboard & live data card polish",
            "Bug fixes across connection flow"
        ]
    ),
    ChangelogEntry(
        version: "0.2.0",
        date: "Apr 2026",
        items: [
            "Wi-Fi OBD adapter support",
            "Improved Bluetooth reconnection",
            "Navbar & tab bar redesign"
        ]
    ),
    ChangelogEntry(
        version: "0.1.0",
        date: "Mar 2026",
        items: [
            "Initial release",
            "Bluetooth OBD2 connection",
            "Live sensor dashboard"
        ]
    ),
]

// MARK: - Views

struct SettingsView: View {
    @ObservedObject var vm: OBDViewModel
    @State private var showLogs = false
    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings section", selection: $showLogs) {
                Text("Preferences").tag(false)
                Text("Logs").tag(true)
            }
            .pickerStyle(.segmented).padding(.horizontal).padding(.top, 8)
            if showLogs { LogsView(vm: vm) } else { SettingsPreferencesView(vm: vm) }
        }
    }
}

private struct SettingsPreferencesView: View {
    @ObservedObject var vm: OBDViewModel
    @AppStorage("aiChatProvider") private var providerRaw: String = AIChatProvider.chatgpt.rawValue
    // The default here only applies before OnDeviceAIMode.loadInitial() has
    // ever run (i.e. this @AppStorage key has no value yet); .onAppear below
    // immediately overwrites it with the migrated value so a returning user
    // never sees this hardcoded .systemModel default override their old
    // on/off toggle setting.
    @AppStorage("onDeviceAIMode") private var aiModeRaw: String = OnDeviceAIMode.systemModel.rawValue
    @AppStorage("trackColorScheme") private var trackColorSchemeRaw = TrackColorScheme.lime.rawValue

    private var aiMode: OnDeviceAIMode { OnDeviceAIMode(rawValue: aiModeRaw) ?? .systemModel }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                // Welcome card
                Section {
                    WelcomeCard()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // Version
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                }

                // Connection
                Section("Connection") {
                    Button("Demo Mode") { vm.connectDemo() }
                        .disabled(vm.isConnecting || vm.connectionState == .connectedToVehicle)
                }

                // Track
                Section {
                    Picker("Color Scheme", selection: $trackColorSchemeRaw) {
                        ForEach(TrackColorScheme.allCases) { scheme in
                            HStack {
                                Circle().fill(scheme.accent).frame(width: 12, height: 12)
                                Text(scheme.displayName)
                            }.tag(scheme.rawValue)
                        }
                    }
                } header: {
                    Text("Track")
                }

                // Diagnostics
                Section {
                    Picker("AI Chat Provider", selection: $providerRaw) {
                        ForEach(AIChatProvider.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    Picker("Apple Intelligence", selection: $aiModeRaw) {
                        ForEach(OnDeviceAIMode.selectableCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text(aiMode.footerDescription)
                        .font(.caption)
                }

                // Changelog
                Section("What's New") {
                    ForEach(changelog) { entry in
                        ChangelogEntryRow(entry: entry)
                    }
                }

                // Footer
                Section {
                    VStack(spacing: 6) {
                        Text("In memory of Rohan")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
        .onAppear {
            // One-time migration from the old boolean toggle — see
            // OnDeviceAIMode.loadInitial(). Only actually changes anything
            // the first time this runs after updating from a version that
            // only had the on/off Toggle; every run after that is a no-op
            // because the new key already has a value by then.
            aiModeRaw = OnDeviceAIMode.loadInitial().rawValue
        }
    }
}

// MARK: - Welcome Card

private struct WelcomeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to DriveOps")
                        .font(.headline)
                    Text("by Abdul Davids")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("A real-time OBD2 diagnostics app for iOS. ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Changelog Row

private struct ChangelogEntryRow: View {
    let entry: ChangelogEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("v\(entry.version)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(entry.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(item)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 2)
    }
}
