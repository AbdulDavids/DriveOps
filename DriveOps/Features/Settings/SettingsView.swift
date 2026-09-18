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
    @AppStorage("aiChatProvider") private var providerRaw: String = AIChatProvider.chatgpt.rawValue
    @AppStorage("onDeviceAIEnabled") private var onDeviceAIEnabled: Bool = true

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

                // Diagnostics
                Section {
                    Picker("AI Chat Provider", selection: $providerRaw) {
                        ForEach(AIChatProvider.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    Toggle("On-Device AI", isOn: $onDeviceAIEnabled)
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text(onDeviceAIEnabled
                         ? "On-device Apple Intelligence explains codes as you open them."
                         : "On-device AI is off. Use \"Ask…\" to open an external provider.")
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
