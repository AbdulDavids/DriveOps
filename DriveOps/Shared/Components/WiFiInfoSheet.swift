//
//  WiFiInfoSheet.swift
//  DriveOps
//

import SwiftUI

struct WiFiInfoSheet: View {
    @ObservedObject var vm: OBDViewModel
    @ObservedObject var wifi: WiFiHelper
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text("Wi-Fi Connection")
                    .font(.title3.bold())
                if let ssid = wifi.currentSSID {
                    HStack(spacing: 4) {
                        Text("Network:")
                            .foregroundStyle(.secondary)
                        Text(ssid)
                            .bold()
                            .foregroundStyle(wifi.looksLikeOBD ? .green : .primary)
                    }
                    .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                wifiStep("1", "Plug adapter into OBD-II port under dashboard")
                wifiStep("2", "Turn car on")
                wifiStep("3", "Go to Settings › Wi-Fi and connect to your OBD Adapter network")
                wifiStep("4", "Come back and tap Connect")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 16) {
                Button(action: { isPresented = false; vm.connectWifi() }) {
                    Label("Connect", systemImage: "wifi")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(vm.isConnecting)
                .controlSize(.large)

                #if os(iOS)
                Button(action: {
                    if let url = URL(string: "App-Prefs:root=WIFI") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Open Wi-Fi Settings")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .onAppear { wifi.refresh() }
    }

    private func wifiStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.green, in: Circle())
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
