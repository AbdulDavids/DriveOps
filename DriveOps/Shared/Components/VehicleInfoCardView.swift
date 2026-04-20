//
//  VehicleInfoCardView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

struct VehicleInfoCardView: View {
    let info: OBDInfo

    @State private var expanded = false

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

                    if let supported = info.supportedPIDs {
                        InfoRow(label: "Supported PIDs", value: "\(supported.count)")
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
