//
//  VehicleInfoCardView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2
import VIN

struct VehicleInfoCardView: View {
    let info: OBDInfo

    @State private var expanded = false

    private var decodedVIN: VIN? {
        guard let raw = info.vin, VIN.isValid(raw) else { return nil }
        return VIN(content: raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Label("Vehicle", systemImage: "car.fill")
                        .font(.headline)
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
                Divider()
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    InfoRow(label: "Protocol", value: info.obdProtocol?.description ?? "—")

                    if let vin = info.vin {
                        InfoRow(label: "VIN", value: vin)
                    }

                    if let decodedVIN {
                        if let manufacturer = decodedVIN.manufacturer {
                            InfoRow(label: "Manufacturer", value: manufacturer)
                        }
                        if let modelYear = decodedVIN.modelYear {
                            InfoRow(label: "Model Year", value: "\(modelYear)")
                        }
                        if let country = decodedVIN.countryName {
                            InfoRow(label: "Origin", value: "\(decodedVIN.flag ?? "") \(country)".trimmingCharacters(in: .whitespaces))
                        }
                    }

                    if let supported = info.supportedPIDs {
                        InfoRow(label: "Supported PIDs", value: "\(supported.count)")
                    }
                }
                .padding(.top, 8)

                if let supported = info.supportedPIDs, !supported.isEmpty {
                    Divider()
                        .padding(.top, 8)

                    // Visibility into what this vehicle actually supports —
                    // cross-reference against Settings → Live Data PIDs
                    // (PIDPickerView), which lets the user choose which of
                    // these (or any other known PID) the poll requests.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Supported PID List")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(supported.sorted { $0.properties.command < $1.properties.command }, id: \.self) { pid in
                            HStack {
                                Text(pid.properties.description)
                                Spacer()
                                Text(pid.properties.command)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
