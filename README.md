# meeting-scribe

Native macOS app for real-time meeting transcription, speaker diarization and AI summaries — for online calls *and* in-person meetings. On-device first, cloud optional.

## Why

Existing open-source options each miss something: Yogurt reads speaker names from the Zoom/Teams/Meet UI instead of analyzing voices (useless in a room), Meetily locks real diarization behind Pro, Vibe is file-based, Screenpipe is not OSI open source. This project is the one we wanted to use.

## Two recording scenarios

| | Online meeting | In-person meeting |
|---|---|---|
| Audio | Mic + system audio, two channels | Single mic, room audio |
| Who is speaking | Partly free: mic = you, system = others | Must come from voice analysis |
| Speaker names | Can read from Zoom/Teams/Meet UI via Accessibility | Not available |

The in-person case is why real speaker diarization is a v1 requirement, not a v2 nice-to-have. No separate channel, no UI names — the only signal is the voice itself.

## Architecture

```
Mic ─────────────┐
                 ├─► Capture (ScreenCaptureKit / AVAudioEngine)
System audio ────┘
                        │
                        ├─► Streaming ASR: Paraformer (offline) or
                        │   Qwen3-ASR via SiliconFlow (online);
                        │   VAD-cut utterances, live transcript
                        │
                        ├─► Diarization: speaker embeddings + clustering
                        │   on audio segments, aligned to transcript
                        │   by timestamp (chunked first, streaming later)
                        │
                        └─► Summarization: local model (Ollama / llama.cpp)
                            or cloud (OpenRouter / SiliconFlow),
                            key stored in macOS Keychain, never in repo
```

- **App**: Swift / SwiftUI, native. No Electron.
- **Capture**: ScreenCaptureKit for system audio (audio-only stream; still needs Screen Recording permission), AVAudioEngine for mic.
- **Transcription**: two engines — offline sherpa-onnx + Paraformer-large (streaming, int8, ~226 MB) and online Qwen3-ASR-1.7B via SiliconFlow.
- **Diarization**: chunked first — segment audio, extract speaker embeddings, cluster, align labels to transcript segments by timestamp. Streaming diarization later.
- **Summaries**: local-first via Ollama; cloud via OpenRouter or SiliconFlow when the user wants a bigger model. API keys live in Keychain / Settings UI only.
- **Privacy**: audio, transcripts and notes stay on the machine by default. Nothing is uploaded unless the user picks a cloud summarizer.

## Roadmap

- **v1**: record mic + system audio, live transcript, local/cloud summary, mic-vs-system speaker split for online calls, chunked diarization for in-person meetings
- **v2**: streaming diarization, speaker enrollment (recognize known voices), action items, search across meetings

## Status

v1 scaffold landed (2026-11-19): SwiftPM package, macOS 14+, Swift 6.

- **Capture**: mic via AVAudioEngine, system audio via ScreenCaptureKit (audio-only stream), both converted to 16 kHz mono
- **Transcription**: two engines — online Qwen3-ASR-1.7B via SiliconFlow (default; one request per utterance, a few seconds of lag) and local sherpa-onnx + Paraformer-large (on-device, fully offline, ~226 MB model downloaded once from Settings). Both are fed by Silero VAD utterance segmentation (~2 MB model, auto-downloaded on first use): each segment is one natural sentence instead of a fixed 6 s window. The local engine streams partial subtitles live while you speak; the online engine finalizes one segment per utterance. Silent windows and sound-only hallucinations are dropped automatically.
- **Diarization**: SpeakerKit (Pyannote backend) on the same chunks for in-person meetings, aligned onto the transcript by time overlap; online meetings use the mic-vs-system channel split
- **Summary**: local Ollama, or OpenRouter / SiliconFlow via OpenAI-compatible chat completions; keys in the Keychain
- **UI**: SwiftUI — round recorder-style transport (red record circle, pause/resume, stop, Cmd+R) with a pulsing recording indicator and elapsed time (paused time excluded), dual-channel spectrum strip (MIC/SYS) while recording, two-line transcript rows (speaker + time above the text), live partial-subtitle footer (local engine), summary pane, settings (provider, models, keys, expected speaker count, theme: system/dark/light). **Minimal window** (from the main window's expand button): a small borderless transparent window — the mic is the only control (tap = start/pause/resume, long-press 0.55 s = stop), a radial spectrum ring around it, and a frosted subtitle band where the middle line is sharp and the outer lines blur and fade as text scrolls. Live subtitles stay in a fixed footer / subtitle band, never inside the List (2026-11-19 EXC_BAD_ACCESS fix).

### Decisions (2026-11-19)

- **Machine**: MacBook Pro M5 Pro, 24 GB — local Paraformer-large int8 (~226 MB) runs on CPU; local Ollama default is Qwen2.5-7B, which fits comfortably in 24 GB unified memory.
- **Meeting apps**: 企业微信 + 腾讯会议 — capture is via ScreenCaptureKit system audio + mic, which works with any app. The Accessibility trick of reading speaker names from the meeting UI (Yogurt's approach) is only verified for Zoom/Teams/Meet, so it is **not** used here; speaker separation comes from the channel split (online) and SpeakerKit diarization (in-person).
- **Language**: Chinese — all models are multilingual (never `.en` variants); summarization defaults to Qwen models.

### Build

```sh
open Package.swift   # in Xcode 16+, macOS 14+
```

Select the MeetingScribe scheme and run. First run downloads the SpeakerKit models from Hugging Face; the offline transcription model (~226 MB) is downloaded once from Settings → 转录 → 本地识别, and the Silero VAD model (~2 MB) downloads itself on first recording. First run will also prompt for microphone and screen recording permission.

> Note: the scaffold was written on a Linux machine with no Xcode; it has since been built in Xcode on the MacBook Pro. The sherpa-onnx (2.0.1) and SpeakerKit call sites were verified against upstream source — if the build complains, paste the errors back and they will be fixed.

## License

MIT
