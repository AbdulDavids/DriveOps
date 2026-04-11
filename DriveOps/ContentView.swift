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

    init(vm: OBDViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    init() {
        _vm = StateObject(wrappedValue: OBDViewModel())
    }

    var body: some View {
        TabView {
            dashboardTab
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.needle")
                }

            logsTab
                .tabItem {
                    Label("Logs", systemImage: "terminal")
                }

            settingsTab
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .sheet(isPresented: $showWifiSheet) {
            wifiInfoSheet
        }
    }

    // MARK: - Tabs

    var dashboardTab: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    connectionCard
                    if let info = vm.obdInfo {
                        vehicleInfoCard(info)
                    }
                    if !vm.liveData.isEmpty {
                        liveDataCard
                    }
                    if let error = vm.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("DriveOps")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }

    var logsTab: some View {
        NavigationStack {
            ScrollView {
                if vm.logs.isEmpty {
                    ContentUnavailableView("No Logs Yet", systemImage: "terminal", description: Text("Connect to a vehicle to see activity"))
                        .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                if !vm.logs.isEmpty {
                    Button("Clear") { vm.logs.removeAll() }
                        .font(.caption)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }

    var settingsTab: some View {
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
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }

    // MARK: - Wi-Fi Info Sheet

    var wifiInfoSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            if let ssid = wifi.currentSSID {
                HStack(spacing: 4) {
                    Text("Network:")
                        .foregroundStyle(.secondary)
                    Text(ssid)
                        .bold()
                        .foregroundStyle(wifi.looksLikeOBD ? .green : .primary)
                }
                .font(.subheadline)
                if wifi.looksLikeOBD {
                    Label("Looks like an OBD adapter!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            } else {
                Text("Make sure you're on your adapter's WiFi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                wifiStep("car.fill", "Plug adapter into OBD-II port (under dashboard, being mysterious)")
                wifiStep("key.fill", "Turn the car on — adapter needs juice")
                wifiStep("gear", "Settings > Wi-Fi, look for \"WiFi_OBDII\" or similar. Home WiFi won't cut it, sorry")
                wifiStep("wifi", "Connect. Yes you lose internet. Your car > Twitter. Probably")
                wifiStep("arrow.uturn.left", "Come back, hit Connect")
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                #if os(iOS)
                Button("Settings") {
                    if let url = URL(string: "App-Prefs:root=WIFI") {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                #endif

                Button("Connect") {
                    showWifiSheet = false
                    vm.connectWifi()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(vm.isConnecting)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .presentationDetents([.medium])
        .onAppear { wifi.refresh() }
    }

    func wifiStep(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Connection Card

    var connectionCard: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusLabel)
                    .font(.subheadline)
                Spacer()
            }

            HStack(spacing: 12) {
                Button(action: { vm.connect() }) {
                    Label("BT", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isConnecting || vm.connectionState == .connectedToVehicle)

                Button(action: { showWifiSheet = true }) {
                    Label("WiFi", systemImage: "wifi")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(vm.isConnecting || vm.connectionState == .connectedToVehicle)
            }

            if vm.connectionState == .connectedToVehicle {
                Button("Disconnect", role: .destructive) {
                    vm.disconnect()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            if vm.isConnecting {
                ProgressView("Connecting…")
                    .font(.caption)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Vehicle Info Card

    func vehicleInfoCard(_ info: OBDInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Vehicle", systemImage: "car.fill")
                .font(.headline)

            Divider()

            infoRow("Protocol", value: info.obdProtocol?.description ?? "—")

            if let vin = info.vin {
                infoRow("VIN", value: vin)
            }

            if let supported = info.supportedPIDs {
                infoRow("Supported PIDs", value: "\(supported.count)")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Live Data Card

    var liveDataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Live Data", systemImage: "gauge.with.needle")
                .font(.headline)

            Divider()

            let sorted = vm.liveData.sorted(by: { $0.key < $1.key })
            ForEach(sorted, id: \.key) { key, value in
                infoRow(key, value: value)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }

    var statusColor: Color {
        switch vm.connectionState {
        case .connectedToVehicle: return .green
        case .connectedToAdapter: return .yellow
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    var statusLabel: String {
        switch vm.connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connectedToAdapter: return "Connected to adapter"
        case .connectedToVehicle: return "Connected to vehicle"
        case .error: return "Error"
        }
    }
}

// MARK: - Previews

#if DEBUG
extension OBDViewModel {
    static func stub(
        state: ConnectionState,
        info: OBDInfo? = nil,
        liveData: [String: String] = [:],
        error: String? = nil
    ) -> OBDViewModel {
        let vm = OBDViewModel(bindServiceState: false)
        vm.connectionState = state
        vm.obdInfo = info
        vm.liveData = liveData
        vm.errorMessage = error
        return vm
    }
}

#endif

#Preview("Disconnected") {
    ContentView(vm: .stub(state: .disconnected))
}

#Preview("Connected – Live Data") {
    ContentView(vm: .stub(
        state: .connectedToVehicle,
        info: (try? JSONDecoder().decode(OBDInfo.self, from: Data(#"{"vin":"1HGBH41JXMN109186"}"#.utf8))),
        liveData: [
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
    ))
}

#Preview("Connecting") {
    ContentView(vm: .stub(state: .connecting))
}

#Preview("Error") {
    ContentView(vm: .stub(state: .error, error: "Could not connect to adapter. Make sure it's paired in Bluetooth settings."))
}
