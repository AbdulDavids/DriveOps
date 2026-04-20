//
//  AIChatProvider.swift
//  DriveOps
//

import Foundation

enum AIChatProvider: String, CaseIterable, Identifiable {
    case chatgpt
    case claude
    case gemini
    case mistral

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatgpt:  return "ChatGPT"
        case .claude:   return "Claude"
        case .gemini:   return "Gemini"
        case .mistral:  return "Mistral"
        }
    }

    func url(for prompt: String) -> URL? {
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let urlString: String
        switch self {
        case .chatgpt:
            urlString = "https://chatgpt.com/?q=\(encoded)"
        case .claude:
            urlString = "https://claude.ai/new?q=\(encoded)"
        case .gemini:
            urlString = "https://gemini.google.com/app?q=\(encoded)"
        case .mistral:
            urlString = "https://chat.mistral.ai/chat?q=\(encoded)"
        }
        return URL(string: urlString)
    }
}
