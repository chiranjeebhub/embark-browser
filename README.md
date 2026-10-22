<p align="center"><img src="brand/embark-icon-1024.png" width="160" alt="Embark icon"></p>

# Embark

An open-source, Arc-style browser for macOS, built natively in Swift with Liquid Glass and
powered by Chromium.

- **Spaces:** each space has its own tint, its own favorites, its own tabs and its own
  profile, so work and personal logins never mix.
- **Vertical tabs** in a sidebar that sits on the window's tint, not in a separate box.
- **Command bar** (⌘T): switch tabs, open favorites, or go to any address or search.
- **Split view** (⌘⇧=): two tabs side by side.
- **Fast:** tabs stay live for instant switching, idle tabs sleep to save memory.

> Status: early. The UI runs on WebKit while the Chromium engine is brought up.
> See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Build

Requires macOS 26 and Xcode 26.

```sh
brew install xcodegen
xcodegen generate
open Embark.xcodeproj
```

That builds the `Embark` scheme, which uses WebKit and needs no downloads. To build with
Chromium, run `scripts/fetch-cef.sh` first, then build the `EmbarkChromium` scheme. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#chromium-via-cef).

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Command bar / new tab | ⌘T or ⌘L |
| Close tab | ⌘W |
| Back / forward / reload | ⌘[ / ⌘] / ⌘R |
| Add to favorites | ⌘D |
| Split view | ⌘⇧= |
| Toggle sidebar | ⌘S |
| Next / previous space | ⌘⌥→ / ⌘⌥← |
| Jump to space 1 to 9 | ⌃1 … ⌃9 |

## License

MIT. See [LICENSE](LICENSE).
