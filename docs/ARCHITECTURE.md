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

Bringing it up on a Mac:

1. `scripts/fetch-cef.sh` downloads the current stable CEF build into `Vendor/cef` and
   builds `libcef_dll_wrapper`.
2. In `project.yml`, stop excluding `Engine/CEF`, add a bridging header that imports
   `CEFBridge.h`, add `Vendor/cef` to the header search paths, link
   `libcef_dll_wrapper.a`, and embed `Chromium Embedded Framework.framework` in
   `Contents/Frameworks`.
3. Add a helper app target built from `HelperMain.mm`, copied four times into
   `Contents/Frameworks` as `Embark Helper.app`, `Embark Helper (GPU).app`,
   `Embark Helper (Renderer).app` and `Embark Helper (Plugin).app`.
4. Set `NSPrincipalClass` to `EMBApplication` and switch the compilation condition to
   `ENGINE_CEF`.

This part has not been compiled yet. Expect a round of fixes on the first real build.
