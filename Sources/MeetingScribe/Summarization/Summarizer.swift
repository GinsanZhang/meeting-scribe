import Foundation

enum SummaryError: Error, LocalizedError {
    case missingAPIKey(provider: String)
    case requestFailed(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider): return "请先在设置里填写 \(provider) 的 API Key"
        case .requestFailed(let message): return "总结请求失败：\(message)"
        case .badResponse: return "总结服务返回了无法解析的结果"
        }
    }
}

protocol Summarizer: Sendable {
    func summarize(transcript: String) async throws -> String
}

enum SummarizerFactory {
    static func make(provider: SummaryProvider, model: String, apiKey: String?) -> any Summarizer {
        switch provider {
        case .ollama:
            return OllamaSummarizer(model: model)
        case .openRouter, .siliconFlow:
            return OpenAICompatibleSummarizer(
                baseURL: provider.chatCompletionsURL!,
                model: model,
                apiKey: apiKey,
                providerName: provider.displayName
            )
        }
    }
}

private func summaryPrompt(for transcript: String) -> String {
    """
    以下是一次会议的文字记录。请用中文输出一份会议总结，结构如下：
    ## 要点
    ## 决定事项
    ## 待办事项（每项写清负责人和截止时间，如记录中提到）
    ## 未决问题
    如果记录中没有相关内容，对应部分写"无"。只根据记录内容总结，不要编造。

    会议记录：
    \(transcript)
    """
}

// MARK: - OpenAI-compatible chat completions (OpenRouter, 硅基流动)

struct OpenAICompatibleSummarizer: Summarizer {
    let baseURL: URL
    let model: String
    let apiKey: String?
    let providerName: String

    func summarize(transcript: String) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw SummaryError.missingAPIKey(provider: providerName)
        }
        let requestBody = ChatCompletionsRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: summaryPrompt(for: transcript))]
        )
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // OpenRouter recommends these; harmless for other providers.
        request.setValue("https://github.com/GinsanZhang/meeting-scribe", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("meeting-scribe", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(requestBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SummaryError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw SummaryError.badResponse
        }
        return content
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double = 0.3
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Local Ollama

/// Local model via Ollama (`ollama serve` + `ollama pull qwen2.5:7b`).
/// Nothing leaves the machine.
struct OllamaSummarizer: Summarizer {
    let model: String
    private let url = URL(string: "http://localhost:11434/api/chat")!

    func summarize(transcript: String) async throws -> String {
        let requestBody = OllamaChatRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: summaryPrompt(for: transcript))],
            stream: false
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SummaryError.requestFailed("Ollama 未响应（请确认 ollama serve 正在运行），HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return decoded.message.content
    }
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

private struct OllamaChatResponse: Decodable {
    struct Message: Decodable { let content: String }
    let message: Message
}
