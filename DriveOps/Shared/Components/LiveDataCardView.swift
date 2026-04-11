//
//  LiveDataCardView.swift
//  DriveOps
//

import SwiftUI

struct LiveDataCardView: View {
    let liveData: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Live Data", systemImage: "gauge.with.needle")
                .font(.headline)

            Divider()

            let sorted = liveData.sorted(by: { $0.key < $1.key })
            ForEach(sorted, id: \.key) { key, value in
                InfoRow(label: key, value: value)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
