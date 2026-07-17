# Video walkthrough — fix list (2026-07-18)

Source: `Screen_Recording_20260717_235305.mp4` (human, on-device, build 0.2.2 / 29).
Method: 52 frames + full audio transcript analysed. The human is **"really, really
disappointed"** — the app crashed repeatedly, nothing worked end-to-end, and no model
ever installed. North star restated by the human: *"I don't want a dummy project or a
playground. I want real value. Make it end-to-end good and better to use. Test
thoroughly before every deploy."*

## What actually happened in the video (evidence)
- Notification tray shows downloads running (Llama-3.2-1B IQ3_M, Qwen3.5-4B Q4_K_M) — the
  0.2.2 foreground-service fix worked, downloads *start* and survive backgrounding.
- **The app crashes the moment a download runs.** System dialog: *"Dhruva AI closed
  because this app has a bug. Try clearing the app's cache."* Happened 4–5 times.
- **No model ever installs.** Settings → "0 models · 0 B used"; Chat → "No model installed
  yet". The crash kills the download before it registers.
- Model detail screen still shows the raw wall-of-quant-files list (rework not shipped).

## Fixes (ranked)

### P0 — blocking, "real value" gate
1. **CRASH: foreground-service permissions missing.** `background_downloader` with
   `Config.runInForeground: always` (my 0.2.2 fix) starts the plugin's `dataSync`
   foreground service (`UIDTJobService`, `foregroundServiceType="dataSync"`). On API 34+
   (emulator/device is API 36) that throws `SecurityException` unless the app holds
   `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC`. Our manifest had neither.
   → **Regression I introduced in 0.2.2.** FIX APPLIED to AndroidManifest.xml. Needs
   rebuild + on-emulator proof.
2. **End-to-end: download → install → chat must complete.** After the crash fix, verify a
   real download finishes, the model appears in Settings/Installed, and chat replies —
   myself, in the emulator, before shipping.

### P1 — usability / "not basic"
3. **Model detail screen** still lists every quant file. Lead with ONE recommended
   download; collapse the rest. (dio+detail agent in flight.)
4. **Per-variant benchmark / effectiveness.** Human: *"which variant is how much
   effective."* Show a quality/size signal per quant (not just size) so the choice is
   informed.
5. **App UI must match the website mockups.** Human: *"the UI is very basic… make it like
   the website."* Website (dhruvaai.vercel.app) chat-streaming / voice-orb / playground
   mockups are the reference. Characters screen is "fine" — leave it.
6. **Download ETA/speed.** Notification always shows "--:-- left". Show real speed + ETA.

### P2 — features / polish
7. **Playground + AI news in-app.** Website has both (roadmap loop 10.5); app has neither.
8. **Website link in About.** About shows "Source on GitHub" only — add dhruvaai.vercel.app.
9. **"Made with ♥ by Ansh Singh Rajput" footer placement** — human flagged positioning.

### Process (added to goal)
10. **Test thoroughly in the emulator before EVERY deploy.** No build reaches Firebase
    until download→install→chat is verified working by me on-device. Repeated shipping of
    a crashing build is the failure mode that produced this video.
