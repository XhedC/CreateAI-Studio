# Platform Support Matrix

Status as of the cross-platform compatibility work (this document, not a commit message, is
the source of truth - update it whenever platform support actually changes).

Legend: ✅ works today · ⚠️ works with a caveat (see note) · ❌ not implemented · — not applicable

| Feature | Android | iOS | Windows | macOS | Linux | Web (public funnel only) |
|---|---|---|---|---|---|---|
| Auth (Supabase) | ✅ | ✅ | ✅ | ✅ | ✅ | — (app not shipped on web) |
| Image AI generation | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| Music AI generation (playback) | ✅ (just_audio) | ✅ (just_audio) | ✅ (just_audio_media_kit) | ✅ (just_audio) | ✅ (just_audio_media_kit) | — |
| Video AI generation (playback) | ✅ (video_player) | ✅ (video_player) | ✅ (fvp) | ✅ (video_player) | ✅ (fvp) | — |
| Funnel builder | ✅ | ✅ | ✅ | ✅ | ✅ | — (editor is not public) |
| Publishing (Phase 7) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (`/f/:slug` is the public surface) |
| Public funnel viewer | ✅ (in-app preview) | ✅ | ✅ | ✅ | ✅ | ✅ (primary target for this route) |
| Image/video/JSON downloads | ✅ (gallery / file picker) | ✅ (gallery / file picker) | ✅ (file picker save dialog) | ✅ (file picker save dialog) | ✅ (file picker save dialog) | n/a |
| Sharing | ✅ (share sheet) | ✅ (share sheet) | ✅ (share_plus; copy-link fallback) | ✅ (share_plus) | ✅ (copy-link fallback) | n/a |
| File/image picking | ✅ | ✅ | ✅ (file_selector) | ✅ (file_selector) | ✅ (file_selector) | n/a |
| Notifications | ❌ (not implemented on any platform) | ❌ | ❌ | ❌ | ❌ | n/a |
| Secure storage (session tokens) | ⚠️ default supabase_flutter storage (SharedPreferences-backed), not a dedicated secure-storage plugin, on every platform equally | ⚠️ | ⚠️ | ⚠️ | ⚠️ | n/a |
| Payments/subscriptions | ❌ (Phase 6 is provider-neutral; no real billing integration yet on any platform, by design) | ❌ | ❌ | ❌ | ❌ | n/a |
| `flutter build` validated this session | ✅ (`apk --debug`) | ❌ no macOS/Xcode host available | ✅ (`windows`, pending Developer Mode) | ❌ no macOS host available | ❌ no Linux host/toolchain available | n/a (no `web/` platform folder added) |

## Notes

- **Music/video playback on Windows/Linux** goes through `just_audio_media_kit` and `fvp`
  respectively - both register themselves *only* as the platform implementation for
  Windows/Linux (see `lib/main.dart`), so Android/iOS/macOS/Web keep using the official
  `just_audio`/`video_player` plugins completely unchanged. `AudioPlayerController` and
  `VideoPlayerWidget` needed zero code changes.
- **Downloads**: video/music downloads always used `FilePicker.saveFile` (already
  cross-platform). Only the image-download path used `gal` (Android/iOS gallery
  integration only, no desktop implementation) - `MediaSaveService`
  (`lib/core/services/media_save_service.dart`) now picks `gal` on mobile and
  `FilePicker.saveFile` on desktop behind one call site.
- **Secure storage**: this is flagged ⚠️ everywhere, not just on new platforms - it was
  already true on Android/iOS before this work and is called out here as a known
  limitation, not a regression. See "Known limitations" in
  `docs/CROSS_PLATFORM_ARCHITECTURE.md`.
- **Notifications**: no notification package exists in `pubspec.yaml` at all - this is a
  from-scratch feature, not a cross-platform gap in an existing one, and is explicitly out
  of scope for this compatibility pass per the brief ("do not add push infrastructure
  unless already required").
- **Builds not validated this session**: iOS and macOS require a macOS host with Xcode;
  Linux desktop requires Linux build tooling (clang/cmake/GTK dev headers) or a Linux
  host. None are available in this Windows-only environment. Their platform folders can
  still be scaffolded and their dependency graphs are confirmed compatible (see the
  Stage 1 audit and the dependency table below) - only the actual native build/link step
  is unverified.
