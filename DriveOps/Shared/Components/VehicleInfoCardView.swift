//
//  VehicleInfoCardView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

struct VehicleInfoCardView: View {
    let info: OBDInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Vehicle", systemImage: "car.fill")
                .font(.headline)

            Divider()

            InfoRow(label: "Protocol", value: info.obdProtocol?.description ?? "—")

            if let vin = info.vin {
                InfoRow(label: "VIN", value: vin)
            }

            if let supported = info.supportedPIDs {
                InfoRow(label: "Supported PIDs", value: "\(supported.count)")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
