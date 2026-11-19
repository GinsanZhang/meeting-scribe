import SwiftUI

/// Summarizer provider, Whisper model, API keys (Keychain).
/// Keys are never shown back and never leave the Keychain.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.summaryProvider) private var providerRaw = SummaryProvider.ollama.rawValue
    @AppStorage(SettingsKey.ollamaModel) private var ollamaModel = SummaryProvider.ollama.defaultModel
    @AppStorage(SettingsKey.openRouterModel) private var openRouterModel = SummaryProvider.openRouter.defaultModel
    @AppStorage(SettingsKey.siliconFlowModel) private var siliconFlowModel = SummaryProvider.siliconFlow.defaultModel
    @AppStorage(SettingsKey.whisperModel) private var whisperModel = "openai_whisper-small"
    @AppStorage(SettingsKey.expectedSpeakers) private var expectedSpeakers = 0

    @State private var openRouterKeyInput = ""
    @State private var siliconFlowKeyInput = ""
    @State private var openRouterKeySaved = false
    @State private var siliconFlowKeySaved = false
    @State private var notice = ""

    var body: some View {
        VStack(spacing: 0) {
        Form {
            Section("总结服务") {
                Picker("服务商", selection: $providerRaw) {
                    ForEach(SummaryProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                if providerRaw == SummaryProvider.ollama.rawValue {
                    TextField("Ollama 模型", text: $ollamaModel)
                    Text("需要本机运行 ollama serve，例如：ollama pull qwen2.5:7b")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if providerRaw == SummaryProvider.openRouter.rawValue {
                    TextField("OpenRouter 模型", text: $openRouterModel)
                    apiKeyRow(
                        label: "OpenRouter API Key",
                        input: $openRouterKeyInput,
                        saved: $openRouterKeySaved,
                        account: SummaryProvider.openRouter.rawValue
                    )
                } else {
                    TextField("硅基流动模型", text: $siliconFlowModel)
                    apiKeyRow(
                        label: "硅基流动 API Key",
                        input: $siliconFlowKeyInput,
                        saved: $siliconFlowKeySaved,
                        account: SummaryProvider.siliconFlow.rawValue
                    )
                }
            }

            Section("转录") {
                Picker("Whisper 模型", selection: $whisperModel) {
                    Text("small（多语言，约 466 MB，默认）").tag("openai_whisper-small")
                    Text("base（多语言，约 145 MB）").tag("openai_whisper-base")
                    Text("large-v3-turbo（最准，约 626 MB）").tag("large-v3-v20240930_626MB")
                    Text("tiny（最快调试用）").tag("openai_whisper-tiny")
                }
                Text("首次运行会从 Hugging Face 下载所选模型，之后离线可用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("线下会议") {
                Stepper(
                    "预期发言人数：\(expectedSpeakers == 0 ? "自动判断" : "\(expectedSpeakers) 人")",
                    value: $expectedSpeakers, in: 0...10
                )
                Text("告诉声纹模型大概几个人，能提高区分准确率；0 为自动判断。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !notice.isEmpty {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480, height: 460)
        .onAppear {
            openRouterKeySaved = KeychainStore.read(account: SummaryProvider.openRouter.rawValue) != nil
            siliconFlowKeySaved = KeychainStore.read(account: SummaryProvider.siliconFlow.rawValue) != nil
        }
    }

    private func apiKeyRow(
        label: String,
        input: Binding<String>,
        saved: Binding<Bool>,
        account: String
    ) -> some View {
        HStack {
            SecureField(label, text: input)
            if saved.wrappedValue {
                Text("已保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("删除") {
                    KeychainStore.delete(account: account)
                    saved.wrappedValue = false
                    notice = "已删除 \(label)"
                }
            } else {
                Button("保存") {
                    guard !input.wrappedValue.isEmpty else { return }
                    if KeychainStore.save(input.wrappedValue, account: account) {
                        input.wrappedValue = ""
                        saved.wrappedValue = true
                        notice = "\(label) 已存入本机 Keychain，不会进入仓库"
                    } else {
                        notice = "保存失败，请重试"
                    }
                }
                .disabled(input.wrappedValue.isEmpty)
            }
        }
    }
}
