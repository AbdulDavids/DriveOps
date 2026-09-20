//
//  ContentView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

struct ContentView: View {
    @StateObject private var vm: OBDViewModel
    @StateObject private var wifi = WiFiHelper()
    @State private var showWifiSheet = false
    @State private var showBTSheet = false

    init(vm: OBDViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    init() {
        _vm = StateObject(wrappedValue: .shared)
    }

    var body: some View {
        TabView {
            DashboardView(vm: vm, showWifiSheet: $showWifiSheet, showBTSheet: $showBTSheet)
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.needle")
                }

            DiagnosticsView(vm: vm)
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }

            TrackView(vm: vm)
                .tabItem {
                    Label("Track", systemImage: "flag.checkered")
                }

            SettingsView(vm: vm)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .sheet(isPresented: $showBTSheet) {
            BluetoothInfoSheet(vm: vm, isPresented: $showBTSheet)
        }
        .sheet(isPresented: $showWifiSheet) {
            WiFiInfoSheet(vm: vm, wifi: wifi, isPresented: $showWifiSheet)
        }
        .onAppear {
            vm.autoConnectIfPossible()
            LiveActivityController.shared.start()
            BackgroundPollController.shared.start()
        }
    }
}

// MARK: - Previews

#if DEBUG
private let previewInfo = try? JSONDecoder().decode(OBDInfo.self, from: Data(#"{"vin":"1HGBH41JXMN109186"}"#.utf8))

private let previewLiveData: [String: String] = [
    "Engine RPM": "2450.0 rpm",
    "Vehicle Speed": "87.0 km/h",
    "Coolant Temp": "91.0 °C",
    "Throttle Position": "23.5 %",
    "Engine Load": "42.0 %",
    "Intake Air Temp": "34.0 °C",
    "MAF": "12.4 g/s",
    "Barometric Pressure": "101.0 kPa",
    "Intake Manifold Pressure": "95.0 kPa",
    "Timing Advance": "14.0 °",
]

#Preview("Disconnected") {
    ContentView(vm: .stub(state: .disconnected))
}

#Preview("Connected – Live Data") {
    ContentView(vm: .stub(state: .connectedToVehicle, info: previewInfo, liveData: previewLiveData))
}

#Preview("Connecting") {
    ContentView(vm: .stub(state: .connecting))
}

#Preview("Error") {
    ContentView(vm: .stub(state: .error, error: "Could not connect to adapter. Make sure it's paired in Bluetooth settings."))
}
#endif
