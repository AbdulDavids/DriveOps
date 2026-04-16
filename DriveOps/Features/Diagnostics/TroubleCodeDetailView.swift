//
//  TroubleCodeDetailView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

struct TroubleCodeDetailView: View {
    let code: TroubleCode
    let ecu: ECUID

    var codePrefix: String { String(code.code.prefix(1)) }

    var codeSystem: String {
        switch codePrefix {
        case "P": return "Powertrain"
        case "B": return "Body"
        case "C": return "Chassis"
        case "U": return "Network"
        default:  return "Unknown"
        }
    }

    var codeSystemIcon: String {
        switch codePrefix {
        case "P": return "engine.combustion"
        case "B": return "car.side"
        case "C": return "steeringwheel"
        case "U": return "network"
        default:  return "questionmark.circle"
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: codeSystemIcon)
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                        .frame(width: 56, height: 56)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(code.code)
                            .font(.system(.title2, design: .monospaced).bold())
                        Text(code.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Details") {
                LabeledContent("System", value: codeSystem)
                LabeledContent("ECU", value: ecu.description)
                LabeledContent("Code Type", value: codeTypeDescription)
            }

            Section {
                Button {
                    openChatGPT()
                } label: {
                    Label("Ask ChatGPT", systemImage: "sparkles")
                }
            } footer: {
                Text("Opens ChatGPT with a pre-filled prompt about this code.")
                    .font(.caption)
            }
        }
        .navigationTitle(code.code)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openChatGPT() {
        let prompt = "I have a \(codeSystem) diagnostic trouble code \(code.code) on my vehicle. The description is: \"\(code.description)\". What does this mean, what are the likely causes, and what should I do to fix it?"
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://chatgpt.com/?q=\(encoded)") else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }

}

private func decodeCode(_ json: String) -> TroubleCode {
    try! JSONDecoder().decode(TroubleCode.self, from: Data(json.utf8))
}

#Preview("Powertrain Code") {
    NavigationStack {
        TroubleCodeDetailView(
            code: decodeCode(#"{"code":"P0420","description":"Catalyst System Efficiency Below Threshold (Bank 1)"}"#),
            ecu: .engine
        )
    }
}

#Preview("Transmission Code") {
    NavigationStack {
        TroubleCodeDetailView(
            code: decodeCode(#"{"code":"P0700","description":"Transmission Control System Malfunction"}"#),
            ecu: .transmission
        )
    }
}

#Preview("Network Code") {
    NavigationStack {
        TroubleCodeDetailView(
            code: decodeCode(#"{"code":"U0100","description":"Lost Communication With ECM/PCM 'A'"}"#),
            ecu: .unknown
        )
    }
}

private extension TroubleCodeDetailView {
    var codeTypeDescription: String {
        guard code.code.count >= 2, let digit = code.code.dropFirst().first.map({ String($0) }), let n = Int(digit) else {
            return "Unknown"
        }
        switch n {
        case 0: return "Generic (SAE)"
        case 1: return "Manufacturer Specific"
        case 2: return "Generic (SAE)"
        case 3: return "Manufacturer Specific"
        default: return "Unknown"
        }
    }
}
