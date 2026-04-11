//
//  LogsView.swift
//  DriveOps
//

import SwiftUI

struct LogsView: View {
    @ObservedObject var vm: OBDViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if vm.logs.isEmpty {
                    ContentUnavailableView(
                        "No Logs Yet",
                        systemImage: "terminal",
                        description: Text("Connect to a vehicle to see activity")
                    )
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
}
