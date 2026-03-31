//
//  ContentView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

struct ContentView: View {
    @StateObject private var vm: OBDViewModel

    init(vm: OBDViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    init() {
        _vm = StateObject(wrappedValue: OBDViewModel())
    }

    var body: some View {
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
                    if !vm.logs.isEmpty {
                        logCard
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
                    Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isConnecting || vm.connectionState == .connectedToVehicle)

                Button(action: { vm.connectDemo() }) {
                    Label("Demo", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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

    // MARK: - Log Card

    var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Debug Log", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Button("Clear") { vm.logs.removeAll() }
                    .font(.caption)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(vm.logs.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .onChange(of: vm.logs.count) { _, _ in
                    proxy.scrollTo(vm.logs.count - 1, anchor: .bottom)
                }
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
