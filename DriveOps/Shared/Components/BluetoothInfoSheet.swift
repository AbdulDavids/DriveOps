//
//  BluetoothInfoSheet.swift
//  DriveOps
//

import SwiftUI

struct BluetoothInfoSheet: View {
    @ObservedObject var vm: OBDViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Bluetooth Connection")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 8) {
                btStep("1", "Plug adapter into OBD-II port under dashboard")
                btStep("2", "Turn car on, accessory mode is fine")
                btStep("3", "Pair adapter in Settings › Bluetooth")
                btStep("4", "Come back and tap Connect")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 16) {
                Button(action: { isPresented = false; vm.connect() }) {
                    Label("Connect", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(vm.isConnecting)
                .controlSize(.large)

                #if os(iOS)
                Button(action: {
                    if let url = URL(string: "App-Prefs:root=Bluetooth") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Open Bluetooth Settings")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(24)
        .presentationDetents([.medium])
    }

    private func btStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.blue, in: Circle())
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
