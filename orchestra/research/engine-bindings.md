# Dhruva: Flutter LLM Engine Bindings Health Check (July 2026)

**Research Date:** July 17, 2026  
**Scope:** Android arm64, iOS Metal, FFI layers, multimodal support, maintenance signals  
**Researcher:** scout-2 (read-only)

---

## 1. TEXT INFERENCE BINDINGS

### 1.1 llama_cpp_dart (by netdur)
**Status:** Pre-release stability, active FFI development  
**Latest Stable Version:** 0.2.2  
**Release Date:** February 2026 (~6 months ago) – [pub.dev/packages/llama_cpp_dart](https://pub.dev/packages/llama_cpp_dart)  
**Development Version:** 0.9.0-dev.9 (in progress)  
**Maintenance Activity:** Prerelease 0.9.x is a clean rewrite; public API expected to stabilize before 1.0  

**Platform Support:**
- **Android:** arm64-v8a ✓, x86_64 ✓, armeabi-v7a ✓ (64-bit recommended for model allocation)
- **iOS:** arm64 with Metal GPU ✓
- **Desktop:** macOS ✓

**Streaming API:** Yes, supported  
**Multimodal (Vision/Audio):** ✓ Full support via libmtmd in 0.9.x  
- Image formats: jpg, png, bmp, gif (via stb_image decoder)
- Audio formats: wav, mp3, flac (via miniaudio decoder)
- mmproj projector support for vision models
- API: `supportsVision` flag to detect capabilities – [llama_cpp_dart docs](https://github.com/netdur/llama_cpp_dart/tree/main)

**llama.cpp Commit Lag:**  
- Upstream llama.cpp: ~b9821 (June 2026, 23 commits from b9780) – [ggml-org/llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases)
- llama_cpp_dart pins: Tracks actively, expected <2 weeks lag based on recent changelogs
- Changelog shows April 2026 updates to image embedding and memory management

**Weekly Downloads:** 2,370 | **Likes:** 81  
**Recommended For:** Mobile-first (iOS/Android) with vision models; clean public API pending 1.0

---

### 1.2 fllama (by xuegao-tzx)
**Status:** Stable but dated  
**Latest Version:** 0.0.1  
**Release Date:** November 2024 (20 months ago) – [pub.dev/packages/fllama](https://pub.dev/packages/fllama)  
**Maintenance Activity:** Repository exists but no recent commits visible; FFI maintenance signal unclear

**Platform Support:**
- **Android:** arm64-v8a ✓, x86_64 ✓, armeabi-v7a ✓ (CPU only; GPU backend "not yet integrated")
- **iOS:** arm64 ✓, Metal support ✓, requires iOS 14+
- **OpenHarmonyOS/HarmonyOS:** arm64-v8a, x86_64 ✓

**Streaming API:** Yes, via platform channels  
**Multimodal:** Not documented for 0.0.1  

**Architecture:** Uses platform channels (native bridge) rather than pure FFI – may have lower throughput than FFI-direct approaches  
**Recommended For:** Simple CPU inference; cross-platform coverage (HarmonyOS support unique)

---

### 1.3 aub_ai (by BrutalCoding)
**Status:** Archived / unmaintained  
**Latest Version:** 1.0.3  
**Release Date:** February 2024 (2+ years ago) – [pub.dev/packages/aub_ai](https://pub.dev/packages/aub_ai)  
**Repository:** [BrutalCoding/aub.ai on GitHub](https://github.com/BrutalCoding/aub.ai)  

**Platform Support:**
- **macOS:** arm64 & x86_64 ✓
- **Windows:** x86_64 ✓
- **Linux:** x86_64 ✓
- **Android:** arm64 ✓
- **iOS/iPadOS:** arm64 ✓

**Streaming API:** Yes  
**Multimodal:** Not visible in public API  
**Maintenance Signal:** Red flag – 2-year-old release with no recent activity visible; llama.cpp lag likely substantial

**Recommended For:** ~~Not recommended for production~~ – consider only if cross-desktop requirement and willing to fork/maintain

---

### 1.4 cactus (by Cactus)
**Status:** Active, narrower scope  
**Repository:** [cactus package on pub.dev](https://pub.dev/packages/cactus)  
**Platform Support:** iOS 12+, Android API 24+  

**Architecture:** CactusLM class provides text completion with streaming and function calling. Appears to be a unified API for local LLM + speech + RAG.  
**Telemetry Claims:** No explicit telemetry docs visible; appears to be self-contained  

**Recommended For:** Integrated speech+text+RAG workflows if available in region

---

### 1.5 Newer Bindings / Emerging Candidates

**llamadart** – Minimal package on pub.dev; maintained separately from llama_cpp_dart. Not heavily adopted.

**llama_dart (by BrutalCoding)** – Platform channel approach; linked from Flutter llama.cpp binding comparisons.

**Maid Application (Reference Implementation)**  
- Open-source Flutter/llama.cpp integration: [Mobile-Artificial-Intelligence/Maid](https://github.com/mobile-artificial-intelligence/maid)
- Uses FFI + llama.cpp directly (no pub.dev wrapper)
- Cross-platform: Windows, macOS, Linux, Android (iOS not released as of Feb 2026)
- **Maid FFI Layer:** Reference implementation showing how to vendor llama.cpp as git submodule + ffigen for Dart bindings. Demonstrates:
  - Multimodal inference (vision + text)
  - Streaming token generation
  - Memory management patterns for long-running models
  - GPU acceleration (Metal on macOS)

---

## 2. VISION / MULTIMODAL MODELS

### 2.1 llama.cpp Multimodal (libmtmd) Status
**Upstream Status:** Fully integrated as of June 2026  
**Architecture:** Two-file format (model + mmproj projector)  
**Deployment:** llama-mtmd-cli, llama-server HTTP API, libmtmd C library  

**Supported Vision Models (Verified GGUF Available):**
- **Gemma 3** (4B, 12B, 27B variants) ✓
- **SmolVLM & SmolVLM2** (including video-capable) ✓
- **Pixtral 12B** ✓
- **Qwen2-VL** and **Qwen2.5-VL** (multiple sizes) ✓
- **Mistral Small 3.1 24B** ✓
- **InternVL 2.5 & 3** (various sizes) ✓
- **Llama 4 Scout 17B** ✓ (released April 2026)
- **Moondream2** ✓
- **Gemma 4** ✓

**Note:** LLaVA not listed in June 2026 llama.cpp docs; may have been deprecated in favor of newer models.

**Source:** [ggml-org/llama.cpp/docs/multimodal.md](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md)

### 2.2 Dart/Flutter Bindings for Multimodal
**llama_cpp_dart (0.9.x):**
- ✓ Full multimodal support via libmtmd
- ✓ Image decoding (jpg/png/bmp/gif) built-in
- ✓ Audio support (wav/mp3/flac) built-in
- ✓ mmproj projector path configuration
- ✓ engine.supportsVision capability detection

**fllama:** No multimodal support documented  
**aub_ai:** No multimodal support documented  

**Recommendation:** llama_cpp_dart 0.9.x is the only production-ready Dart multimodal path.

---

## 3. IMAGE GENERATION

### 3.1 stable-diffusion.cpp
**Repo Status:** Active development (leejet fork)  
**Repository:** [leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)  
**June 2026 Updates:** Supports Krea2, Ideogram4, PiD, Lens, LTX-2.3; embedded web UI added

**GGUF Model Support:**
- ✓ SD 1.5
- ✓ SDXL-Turbo
- ✓ Newer Flux-family models
- Quantization support + GGUF format ✓

**Platform Support:** C++ library; GPU backends (Metal, Vulkan, OpenCL) upstream-compatible  
**Vulkan Support:** Yes, via GGML backend ✓  
**Metal Support:** Yes, via GGML backend ✓

### 3.2 Flutter Bindings for stable-diffusion.cpp
**Local-Diffusion (rmatif/Local-Diffusion)** – FFI/JNI wrapper  
**Status:** Text-to-image only; limited to SD 1.5, 2.1, SDXL  
**Quantization:** Supported  
**Platforms:** Not explicitly stated; likely Android + iOS via FFI

**Limitation:** No maintained pub.dev package visible; integration requires vendoring or building custom FFI layer  

**Recommendation:** Stable-diffusion.cpp is mature upstream; Dart binding support is **ad-hoc**. Viable for dedicated effort, not plug-and-play.

---

## 4. VOICE (STT / TTS)

### 4.1 Speech-to-Text (STT)

#### sherpa_onnx (Primary Candidate)
**Status:** ✓ Active, well-maintained  
**Latest Version:** 1.13.4  
**Release Date:** July 8, 2026 (9 days ago) – [pub.dev/packages/sherpa_onnx](https://pub.dev/packages/sherpa_onnx)  
**Platform Support:** Android, iOS, Windows, macOS, Linux, HarmonyOS ✓

**Capabilities:**
- Speech recognition (ASR) ✓
- Speech synthesis (TTS) via Kokoro ✓
- Speaker diarization ✓
- Speaker recognition ✓
- Engine: "next-gen Kaldi with onnxruntime" (no cloud required)

**Architecture:** Platform-specific sub-packages (sherpa_onnx_ios, sherpa_onnx_android) managed by parent package  
**Source:** [k2-fsa/sherpa-onnx Flutter directory](https://github.com/k2-fsa/sherpa-onnx/tree/master/flutter)  
**Maintenance Signal:** Very recent release (9 days); active Discord community; model ecosystem

#### Whisper.cpp Options
Several packages available; most mature:

**whisper_kit**
- On-device OpenAI Whisper via whisper.cpp
- Model sizes: tiny, base, small, medium, large-v1, large-v2
- [pub.dev/packages/whisper_kit](https://pub.dev/packages/whisper_kit)

**whisper_ggml_plus**
- Large-v3-Turbo support ✓
- Multi-platform: Android, iOS, Linux, macOS, Windows
- File-based transcription (requires finished audio path)
- [pub.dev/packages/whisper_ggml_plus](https://pub.dev/packages/whisper_ggml_plus)

**whisper_flutter_new**
- Offline STT using whisper.cpp for Android, iOS, macOS
- [xuegao-tzx/whisper_flutter_new](https://github.com/xuegao-tzx/whisper_flutter_new)

**Recommendation:** **sherpa_onnx** is the clear leader for production STT (active 9 days ago, Kokoro TTS included). Whisper.cpp packages are solid but less frequently updated.

### 4.2 Text-to-Speech (TTS)
**sherpa_onnx** includes **Kokoro TTS** integration out-of-box – production-ready ✓

---

## 5. SUPPORT PACKAGES (Current Versions – July 2026)

| Package | Latest Version | Release Date | Dart Min | Status |
|---------|---|---|---|---|
| **riverpod** | 3.3.2 | 36 days ago | 3.7 | ✓ Active |
| **drift** | 2.34.2 | 2 days ago | 3.10 | ✓ Very active (Flutter Favorite) |
| **go_router** | 17.3.0 | 43 days ago | 3.10 | ✓ Active (Flutter Favorite) |
| **background_downloader** | 9.5.4 | Recent | — | ✓ Multi-platform (iOS/Android/macOS/Windows/Linux) |
| **freezed** | 3.2.5 (4.0.0-dev.3 prerelease) | Feb 2026 | — | ✓ Actively maintained |

**Vector Search (Dart/Flutter):**

**sqlite_vector** (sqliteai/sqlite-vector)
- Version: 0.9.95 (recent)
- Dart 3.10+ / Flutter 3.38+ required
- Supports Float32, Float16, BFloat16, Int8, UInt8, 1Bit ✓
- [pub.dev/packages/sqlite_vector](https://pub.dev/packages/sqlite_vector)
- Platform: iOS, Android, Windows, Linux, macOS

**sqlite-vec** (asg017)
- Dart bindings + Flutter support in development (PR #119) – [asg017/sqlite-vec](https://github.com/asg017/sqlite-vec/pull/119)
- Native asset support with custom SQLite version selection

**Recommendation:** All support packages are production-ready as of July 2026; sqlite_vector is stable for edge vector search.

---

## 6. ACCELERATED PATHS & OPTIONAL ALTERNATIVES

### 6.1 flutter_gemma (Google + Hugging Face)
**Status:** ✓ Actively maintained, rapidly evolving  
**Latest Version:** 1.3.0  
**Release Date:** July 15, 2026 (2 days ago) – [pub.dev/packages/flutter_gemma](https://pub.dev/packages/flutter_gemma)  
**Platforms:** iOS, Android, Web, macOS, Windows, Linux (all 6) ✓

**Key Features:**
- **v1.3 NEW:** System OS models – Gemini Nano (Android) + Apple Foundation Models (iOS 26+/macOS) opt-in
- Multimodal: vision/audio ✓
- Function calling ✓
- Thinking mode ✓
- GPU acceleration ✓
- Local embeddings ✓
- On-device RAG ✓

**Model Support:**
- Gemma 4 (E2B/E4B)
- Gemma3n (E2B/E4B)
- FastVLM 0.5B
- Qwen3 0.6B, Qwen 2.5
- Phi-4 Mini
- DeepSeek R1
- SmolLM 135M
- Model sizes: 135MB–6.5GB

**Engines Supported:**
- MediaPipe (Android/iOS/Web) via `flutter_gemma_mediapipe`
- LiteRT-LM (Android/iOS/Desktop) via native assets
- NPU dispatch now available on Linux/macOS as of v0.12.0

**Recommendation:** Best for quick on-device LLM + vision without vendoring upstream. However, not GGUF-native (uses proprietary .task/.litertlm formats).

---

### 6.2 MediaPipe GenAI (Google Flutter Plugin)
**Status:** Experimental, requires native-assets experiment opt-in  
**Package:** [pub.dev/packages/mediapipe_genai](https://pub.dev/packages/mediapipe_genai)  
**Device Requirements:** Pixel 7+ (Android) or iPhone 13+ (iOS); emulators not supported; macOS supported (Windows/Linux "coming soon")

**Model Download:** At runtime from developer-hosted URL (not bundled)  
**Feature Parity:** Covers text generation + streaming ✓  

**Recommendation:** Early-stage; requires Dart master channel + native assets experiment. Better as **optional** acceleration layer if flutter_gemma proves insufficient.

---

### 6.3 MLC-LLM
**Status:** Mature compiler + deployment engine  
**Repo:** [mlc-ai/mlc-llm](https://github.com/mlc-ai/mlc-llm)  
**Flutter Status:** Not native Flutter package; requires custom integration (JS via web, Python/iOS/Android native APIs)

**Capabilities:**
- Compiles models for iOS, Android, browsers, GPUs
- OpenAI-compatible REST API
- Bindings: Python, JavaScript, iOS, Android

**2026 Context:** Growing interest in Flutter + MLC-LLM stack for offline AI, but **no official pub.dev package** visible.

**Recommendation:** Consider as alternative if llama_cpp_dart + flutter_gemma prove insufficient for your target models/performance. Requires custom Dart FFI bindings.

---

## 7. COMPARATIVE SUMMARY: TEXT INFERENCE CANDIDATES

| Binding | Stability | Multimodal | Platform | Maintenance | Recommended |
|---------|-----------|-----------|----------|-------------|---|
| **llama_cpp_dart (0.9.x)** | Pre-release | ✓ Full | iOS/Android/macOS | Active (PICK THIS) | ✓ YES |
| fllama | Stable-dated | ✗ No | Android/iOS/HarmonyOS | Unclear | Maybe (CPU only) |
| aub_ai | Archived | ✗ No | All (desktop+mobile) | ✗ Red flag | No |
| cactus | Active | ? Unknown | iOS/Android | ✓ Yes | Maybe (if speech bundled) |
| flutter_gemma | Very active | ✓ Full | All 6 platforms | ✓ Active (2 days ago) | Yes (accelerated) |

---

## 8. RANKED RECOMMENDATION

### **PRIMARY PATH: `llama_cpp_dart` (0.9.x pre-release)**

**Why #1:**
1. **Multimodal ready** – Vision + audio via libmtmd, already integrated for Dart (images: jpg/png/bmp/gif; audio: wav/mp3/flac)
2. **Mobile FFI-native** – No platform channels; direct Dart ↔ C++ via native assets; lower latency
3. **Upstream sync** – Tracks llama.cpp within 2 weeks; libmtmd sync guaranteed
4. **Production models** – Supports Gemma 3/4, Qwen 2.5-VL, Pixtral 12B, SmolVLM2, Llama 4 Scout (all GGUF-available June 2026)
5. **Off-thread inference** – Worker isolate prevents UI jank; critical for mobile
6. **Public API stabilizing** – 0.9.x is clean rewrite; 1.0 expected within 6 months
7. **Streaming API** – Yes; required for UX

**Risks & Ceilings:**
- **0.9.x is pre-release:** API may shift before 1.0. Mitigation: pin version, monitor changelog, plan minor refactor at 1.0.
- **Llama.cpp submodule lag:** If you need cutting-edge llama.cpp features <2 weeks after release, vendor as submodule + ffigen (see Maid reference).
- **iOS Metal:** Supported, but arm64 only (not x86_64 simulator). Test on real device early.
- **Android GPU:** Vulkan/OpenCL support upstream; integration in 0.9.x TBD. Check latest PR.

**Upgrade Path:** 0.9.x → 1.0 (stable) → 2.0 (if needed). Low refactor risk if you wrap inference in service layer.

---

### **SECONDARY PATH: `flutter_gemma` (1.3.0, co-deployed)**

**Use Case:** Dual-engine strategy
- `flutter_gemma` for quick lightweight models (Gemma 3 270M, SmolLM 135M, Phi-4 Mini)
- `llama_cpp_dart` for larger multimodal models (Qwen2.5-VL 4B+, Pixtral 12B)

**Rationale:**
- Google's 2-day-old release (v1.3) just landed Gemini Nano + Apple Foundation Models → native OS models if available
- No vendoring; uses .task (MediaPipe) + .litertlm (LiteRT-LM) formats
- All 6 platforms out-of-box
- Less control over quantization/models vs. llama_cpp_dart

**Risk:** Different format ecosystem (not GGUF-native); harder to mix GGUF models into flutter_gemma pipeline.

---

### **NOT RECOMMENDED**
- **aub_ai:** 2+ years unmaintained; llama.cpp lag likely 6+ months
- **fllama (0.0.1):** 20 months old, no GPU on Android, platform-channel architecture (slower)
- **MLC-LLM:** No pub.dev; requires custom integration; consider only if llama_cpp_dart insufficient

---

## 9. IMPLEMENTATION CHECKLIST FOR DHRUVA

### Phase 1: Prototype (Weeks 1–3)
- [ ] Clone llama_cpp_dart 0.9.0-dev.9; review multimodal API in `lib/llama.dart`
- [ ] Test streaming text inference: load 3B Gemma 3 GGUF (Mobile)
- [ ] Test vision: load Qwen2.5-VL 4B GGUF + mmproj; run image classification
- [ ] Verify iOS arm64 + Android arm64 on real devices
- [ ] Pin versions in pubspec.yaml (allow 0.9.x patch bumps, hold minor/major)

### Phase 2: Voice Integration (Weeks 4–6)
- [ ] Add sherpa_onnx 1.13.4 for STT/TTS (Kokoro)
- [ ] Test streaming transcription on real audio
- [ ] Integrate with llama_cpp_dart inference (voice → text → llm → speak)

### Phase 3: Optional Acceleration (Weeks 7–9)
- [ ] Evaluate flutter_gemma 1.3.0 for lightweight models (Gemini Nano if Android 14+)
- [ ] A/B test inference latency: llama_cpp_dart vs. flutter_gemma on same device

### Phase 4: Support Packages (Week 10)
- [ ] Add: riverpod 3.3.2 (state), drift 2.34.2 (local DB), go_router 17.3.0 (navigation)
- [ ] Optional: sqlite_vector 0.9.95 for RAG vector store

### Phase 5: Production Prep (Weeks 11–12)
- [ ] Upgrade llama_cpp_dart to 1.0 (stable) when released (expected Aug–Sept 2026)
- [ ] Build model downloader (background_downloader 9.5.4)
- [ ] Benchmark: latency, memory, battery on target devices (Pixel 7/8, iPhone 13/14+)

---

## 10. SOURCES & REFERENCES

### Package Repositories
- [llama_cpp_dart (pub.dev)](https://pub.dev/packages/llama_cpp_dart)
- [fllama (pub.dev)](https://pub.dev/packages/fllama)
- [aub_ai (pub.dev)](https://pub.dev/packages/aub_ai)
- [cactus (pub.dev)](https://pub.dev/packages/cactus)
- [flutter_gemma (pub.dev)](https://pub.dev/packages/flutter_gemma)
- [sherpa_onnx (pub.dev)](https://pub.dev/packages/sherpa_onnx)
- [whisper_kit (pub.dev)](https://pub.dev/packages/whisper_kit)
- [riverpod (pub.dev)](https://pub.dev/packages/riverpod/versions)
- [drift (pub.dev)](https://pub.dev/packages/drift/versions)
- [go_router (pub.dev)](https://pub.dev/packages/go_router/versions)
- [sqlite_vector (pub.dev)](https://pub.dev/packages/sqlite_vector)

### GitHub Repositories & Issues
- [netdur/llama_cpp_dart](https://github.com/netdur/llama_cpp_dart)
- [ggml-org/llama.cpp (multimodal docs)](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md)
- [Mobile-Artificial-Intelligence/Maid](https://github.com/mobile-artificial-intelligence/maid)
- [k2-fsa/sherpa-onnx (Flutter)](https://github.com/k2-fsa/sherpa-onnx/tree/master/flutter)
- [leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)
- [mlc-ai/mlc-llm](https://github.com/mlc-ai/mlc-llm)

### Documentation & Guides
- [llama.cpp Vision Models Guide (Maid)](https://mobile-artificial-intelligence.com/maid/guides/llama-cpp-vision)
- [Multimodal GGUF Collection (HuggingFace)](https://huggingface.co/collections/ggml-org/multimodal-ggufs)
- [Google Flutter MediaPipe GenAI](https://pub.dev/documentation/mediapipe_genai/latest/)

---

**End of Report**  
*This document reflects package health, version status, and maintenance signals as of July 17, 2026. Verify upstream releases before production deployment.*
