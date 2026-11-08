# ORBIT 初版验证说明

Release candidate verification: 2026-11-08 · Windows 11 x64 · Flutter 3.47.9 / Dart 3.13.7 / Python 3.11.

## 0.7.1 master bus

- Flutter analysis: no issues. Full M3 suite: 42 tests pass, including master-node selection/editing with no audio object, input-type restrictions, graph serialization, context-safe deletion and undo.
- Python suite: 48 tests pass. New master checks prove exact post-binaural +6 dB gain without re-spatialization; delayed master effects in late previews match the full render; unsupported independent inputs/HRTF are rejected; and masterGraph survives CLI edits and portable bundle reopening.
- Pipeline is summed binaural audio → master gain → optional masterGraph → sample-peak protection. Old scenes default to bypass. Source-level STFT is not a master-bus meter. Master history is included in preview pre-roll. This is not LUFS normalization or a true-peak limiter.
- Native Windows UI is compiled and widget-tested, not fully live-interaction verified.
- Synthetic integration: the actual CLI HTTP service and shipped client created a portable project and rendered a 7-second 48 kHz FLAC24 file. Demucs htdemucs_6s also separated a synthetic one-second signal on CUDA into vocals/piano/guitar. No private music or tokens are packaged.

## Native Windows validation boundary

An earlier build exited inside flutter_windows.dll during desktop accessibility traversal. Related upstream reports include [Flutter #195399](https://github.com/flutter/flutter/issues/195399) and [Flutter #190357](https://github.com/flutter/flutter/issues/190357). Similar symptoms do not prove the exact same root cause.

High-frequency Material sliders use custom controls that keep a stable accessible node, and Windows playback is isolated in a Python process. Automated regression tests cover the controls. A complete native-window/accessibility retest has not been performed. Therefore the native exit is **not claimed conclusively fixed**.

## Scope and limits

- Windows x64 Flutter UI; Python/FFmpeg must be available locally.
- Preview is a maximum 20-second pre-render, not realtime DSP while dragging.
- Measured KEMAR binaural stereo, not Dolby Atmos ADM/BWF or E-AC-3 JOC.
- 48 kHz render; sample-peak protection, not a true-peak limiter or loudness normalizer.
- Demucs only. BS-RoFormer and SCNet are not integrated.
- The bundled example uses only procedural rain/wind and position keyframes. No private music is distributed.
- CLI/API work on saved files, not the live GUI or its unsaved state. GUI/API concurrent edits are not protected by a cross-process lock; API in-place edits require a revision and explicitly requested overwrite. API listens only on 127.0.0.1 and should not be internet-exposed. Jobs/history are in memory, serial within this service, not globally serialized against GUI jobs. Cancellation is not undo; already-published results remain. See AUTOMATION.md and backend/openapi.json.
- API path confinement is not an OS/network sandbox. DSP uses memory-resident audio; the configurable 600-second API span limit is not a memory quota. FFmpeg/model dependencies and first-use model downloads are unchanged.
- Workspaces have three swap-capable regions plus one adjustable bottom region; arbitrary split/merge/floating windows are not implemented. Graph parameters are static; existing object automation remains available. Spectrum is manually computed for a selected object's source/clip/nodes, not live master-bus output or spectral repair. Playback-rate changes also change pitch. See WORKFLOWS.md.
