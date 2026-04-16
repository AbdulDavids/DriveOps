//
//  SettingsView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

struct SettingsView: View {
    @ObservedObject var vm: OBDViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Connection") {
                    Button("Demo Mode") { vm.connectDemo() }
                        .disabled(vm.isConnecting || vm.connectionState == .connectedToVehicle)
                }

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
