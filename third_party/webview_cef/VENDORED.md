# Vendored `webview_cef`

This is a Linux-only copy of [`webview_cef` 0.2.2](https://pub.dev/packages/webview_cef).
It lives in the repo so the Linux wheel direction can be corrected without
patching the pub cache after every `flutter pub get`.

## Changes from upstream

- `pubspec.yaml` declares only the Linux platform. The macOS and Windows
  implementations are not vendored because this app only embeds a webview on
  Linux; the other platforms keep their native preview.
- `common/webview_handler.cc` no longer flips `deltaY` on Linux. Upstream flips
  it for both Windows and Linux, which made the page scroll opposite to the
  wheel. The flip is still applied on Windows.

## Updating

Replace `lib/`, `common/`, `linux/` and `third/download.cmake` with the new
upstream release, then re-apply the two changes above. Keep the CEF binaries out
of git: `third/cef/` is ignored and is downloaded by `third/download.cmake` on
the first build (about 200 MB compressed, roughly 3 GB extracted).
