# Architecture

Embark is a native SwiftUI app for macOS 26. The interface (sidebar, spaces, command bar,
split view) is pure SwiftUI with Liquid Glass. Web pages are rendered by an engine behind a
small protocol, so the UI never depends on Chromium directly.

```
SwiftUI views ──► BrowserStore (spaces, profiles, favorites, tabs; saved as JSON)
      │
      └──► PagePool ──► BrowserEngine ──► CEFEngine (Chromium, the shipping engine)
                                     └──► WebKitEngine (development engine, no downloads)
```

## Concepts

- **Profile:** its own cookies, logins, cache and history on disk.
- **Space:** a name, a tint, one profile, its own favorites and its own tabs. Switching
  space switches account. There is no separate "pinned" list: a space's favorites are its
  pinned sites.
- **Favorites** behave like apps: opening one reuses its tab if it is already open.
- **PagePool** keeps one live page per tab so switching is instant, and closes pages that
  have not been looked at for 30 minutes. They reload when shown again.

## Engines

`Engine/BrowserEngine.swift` defines `BrowserEngine`, `BrowserPage` and the delegate.
The build flag picks the engine: `ENGINE_WEBKIT` (default today) or `ENGINE_CEF`.

### Chromium via CEF

Code lives in `Engine/CEF`:

- `CEFBridge.h/.mm`: Objective-C++ wrapper around CEF. One `CefRequestContext` per
  profile directory keeps logins apart. Popups become tabs. AppKit keeps its run loop and
  CEF runs on an external message pump.
- `CEFEngine.swift`: the Swift `BrowserEngine` on top of the bridge.
- `HelperMain.mm`: entry point for the Chromium helper processes.

Building it:

```sh
scripts/fetch-cef.sh          # downloads stable CEF into Vendor/cef, builds libcef_dll_wrapper
xcodegen generate
xcodebuild -scheme EmbarkChromium build   # or pick the EmbarkChromium scheme in Xcode
```

How the pieces fit:

- `EmbarkChromium` compiles the same app with `ENGINE_CEF`, the bridging header
  `Engine/CEF/Embark-Bridging-Header.h`, and links `libcef_dll_wrapper`. Its
  `NSPrincipalClass` is `EMBApplication`, which CEF requires.
- The Chromium framework is loaded at runtime by `CefScopedLibraryLoader`, so nothing
  links against it. `scripts/embed-cef.sh` copies it into `Contents/Frameworks`.
- `EmbarkHelper` is built once from `HelperMain.mm` and copied by the same script as
  `Embark Helper`, `(GPU)`, `(Renderer)`, `(Plugin)` and `(Alerts)`.
- The Chromium sandbox is off for now (`no_sandbox`). Turning it on means linking
  `cef_sandbox` into the helpers.

CI builds both engines on every pull request (`.github/workflows/build.yml`).
