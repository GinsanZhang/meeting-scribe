import SwiftUI

/// Summarizer provider, transcription engine, API keys (Keychain).
/// Keys are never shown back and never leave the Keychain.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.summaryProvider) private var providerRaw = SummaryProvider.ollama.rawValue
    @AppStorage(SettingsKey.ollamaModel) private var ollamaModel = SummaryProvider.ollama.defaultModel
    @AppStorage(SettingsKey.openRouterModel) private var openRouterModel = SummaryProvider.openRouter.defaultModel
    @AppStorage(SettingsKey.siliconFlowModel) private var siliconFlowModel = SummaryProvider.siliconFlow.defaultModel
    @AppStorage(SettingsKey.transcriptionEngine) private var transcriptionEngineRaw = TranscriptionEngineKind.online.rawValue
    @AppStorage(SettingsKey.expectedSpeakers) private var expectedSpeakers = 0

    @State private var openRouterKeyInput = ""
    @State private var siliconFlowKeyInput = ""
    @State private var openRouterKeySaved = false
    @State private var siliconFlowKeySaved = false
    @State private var notice = ""
    @State private var downloadProgress: Double?
    @State private var modelDownloaded = SherpaModelManager.isDownloaded

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
                Picker("识别引擎", selection: $transcriptionEngineRaw) {
                    ForEach(TranscriptionEngineKind.allCases) { kind in
                        Text(kind.displayName).tag(kind.rawValue)
                    }
                }
                if transcriptionEngineRaw == TranscriptionEngineKind.online.rawValue {
                    apiKeyRow(
                        label: "硅基流动 API Key",
                        input: $siliconFlowKeyInput,
                        saved: $siliconFlowKeySaved,
                        account: SummaryProvider.siliconFlow.rawValue
                    )
                    Text("在线识别调用硅基流动的 Qwen3-ASR-1.7B，按音频时长计费；按自然语句切分后逐句发送，有几秒延迟。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // 本地识别：sherpa-onnx + Paraformer-large（中英双语），
                    // 完全离线。模型不在仓库里，首次使用需下载。
                    if modelDownloaded {
                        Text("离线模型已下载（Paraformer-large，中英双语，约 226 MB），可离线识别。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("本地识别使用 Paraformer-large（中英双语），完全离线；首次使用需下载约 226 MB 模型。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let downloadProgress {
                            ProgressView(value: downloadProgress)
                            Text("正在下载离线模型… \(Int(downloadProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("下载离线模型") {
                                downloadProgress = 0
                                notice = ""
                                Task {
                                    do {
                                        try await SherpaModelManager.download { progress in
                                            Task { @MainActor in
                                                downloadProgress = progress
                                            }
                                        }
                                        await MainActor.run {
                                            downloadProgress = nil
                                            modelDownloaded = true
                                            notice = "离线模型已下载完成，可切换到本地识别"
                                        }
                                    } catch {
                                        await MainActor.run {
                                            downloadProgress = nil
                                            notice = "下载失败：\(error.localizedDescription)"
                                        }
                                    }
                                }
                            }
                            .disabled(downloadProgress != nil)
                        }
                    }
                }
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
            modelDownloaded = SherpaModelManager.isDownloaded
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
