//
//  LiveDataCardView.swift
//  DriveOps
//

import SwiftUI

struct LiveDataCardView: View {
    let liveData: [String: String]
    var isWide: Bool = false

    private var sorted: [(key: String, value: String)] {
        liveData.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Live Data", systemImage: "gauge.with.needle")
                .font(.headline)

            Divider()

            if isWide {
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(sorted, id: \.key) { key, value in
                        InfoRow(label: key, value: value)
                    }
                }
            } else {
                ForEach(sorted, id: \.key) { key, value in
                    InfoRow(label: key, value: value)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
