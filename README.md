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
                        ├─► Streaming ASR: whisper.cpp (Metal, on-device)
                        │   5s sliding window + VAD, live transcript
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
- **Transcription**: whisper.cpp, streaming mode, Metal acceleration. `base`/`small` models are plenty on Apple Silicon.
- **Diarization**: chunked first — segment audio, extract speaker embeddings, cluster, align labels to transcript segments by timestamp. Streaming diarization later.
- **Summaries**: local-first via Ollama; cloud via OpenRouter or SiliconFlow when the user wants a bigger model. API keys live in Keychain / Settings UI only.
- **Privacy**: audio, transcripts and notes stay on the machine by default. Nothing is uploaded unless the user picks a cloud summarizer.

## Roadmap

- **v1**: record mic + system audio, live transcript, local/cloud summary, mic-vs-system speaker split for online calls, chunked diarization for in-person meetings
- **v2**: streaming diarization, speaker enrollment (recognize known voices), action items, search across meetings

## Status

Just started — repo created, scaffolding next.

## License

MIT
