//
//  TroubleCodeDetailView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2
import FoundationModels
import AppleIntelligenceForSwiftUI

struct TroubleCodeDetailView: View {
    let code: TroubleCode
    let ecu: ECUID

    @AppStorage("aiChatProvider") private var providerRaw: String = AIChatProvider.chatgpt.rawValue
    @AppStorage("onDeviceAIEnabled") private var onDeviceAIEnabled: Bool = true

    private var provider: AIChatProvider { AIChatProvider(rawValue: providerRaw) ?? .chatgpt }

    @State private var explanation: String = ""
    @State private var isGenerating: Bool = false
    @State private var explanationError: String? = nil

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

            if #available(iOS 26, *), onDeviceAIEnabled {
                aiExplanationSection
            }

            Section {
                Button {
                    openInAIChat()
                } label: {
                    Text("Ask \(provider.displayName)")
                }
            } footer: {
                Text("Opens \(provider.displayName) with a pre-filled prompt.")
                    .font(.caption)
            }
        }
        .navigationTitle(code.code)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if #available(iOS 26, *), onDeviceAIEnabled {
                await generateExplanation()
            }
        }
    }

    @available(iOS 26, *)
    @ViewBuilder
    private var aiExplanationSection: some View {
        Section {
            if let error = explanationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(explanation.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .animation(.easeIn(duration: 0.15), value: explanation)
            }
        } header: {
            Text("Mechanic")
                .foregroundStyle(LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.45, blue: 0.22),
                        Color(red: 0.91, green: 0.22, blue: 0.62),
                        Color(red: 0.36, green: 0.56, blue: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .fontWeight(.semibold)
        } footer: {
            Text("Generated on-device. May not be accurate.")
                .font(.caption)
        }
    }

    @available(iOS 26, *)
    private func generateExplanation() async {
        guard SystemLanguageModel.default.isAvailable else {
            explanationError = "Apple Intelligence is not available on this device."
            return
        }
        isGenerating = true
        explanation = ""
        explanationError = nil

        let session = LanguageModelSession(instructions: """
            You are a concise automotive diagnostic assistant. \
            Explain OBD-II trouble codes in plain language for a car owner — not a mechanic. \
            Structure your response in three short paragraphs: \
            1) What it means, 2) Likely causes, 3) What to do next. \
            Keep the total response under 120 words. No bullet points. No headings.
            """)

        let prompt = "\(codeSystem) code \(code.code): \"\(code.description)\". ECU: \(ecu.description)."

        do {
            let stream = session.streamResponse(to: prompt)
            for try await snapshot in stream {
                explanation = snapshot.content
            }
        } catch LanguageModelSession.GenerationError.guardrailViolation,
                LanguageModelSession.GenerationError.refusal {
            explanationError = "Could not generate explanation for this code."
        } catch {
            explanationError = "Apple Intelligence unavailable. \(error.localizedDescription)"
        }
        isGenerating = false
    }

    private func openInAIChat() {
        let prompt = "I have a \(codeSystem) diagnostic trouble code \(code.code) on my vehicle. The description is: \"\(code.description)\". What does this mean, what are the likely causes, and what should I do to fix it?"
        guard let url = provider.url(for: prompt) else { return }
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
