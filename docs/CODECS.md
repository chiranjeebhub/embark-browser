# Video codecs (H.264, AAC)

The prebuilt CEF that `scripts/fetch-cef.sh` downloads is built without Chromium's
proprietary codecs, so MP4 files with H.264 video or AAC audio do not play. WebM, VP9, AV1 and
Opus work. Streaming sites with DRM (Netflix, Disney+) are a separate problem: they need
Widevine, which Google licenses per browser.

## What Embark does about it

Pages that need H.264 run on macOS's WebKit instead, which has Apple's codecs (and FairPlay
for the streaming sites). `Models/ProtectedMedia.swift` lists the sites that go there
automatically: copy-protected streaming sites, and video sites that serve only H.264 (X,
Instagram, Reddit, Twitch, Vimeo, TikTok).

On any other site, the media script (`Models/Media.swift`) watches for video that fails for
lack of H.264: a media element that errors on an MP4 or HLS source, a `MediaSource` that
refuses an H.264 type, or a site that asks for H.264 and never for VP9 or AV1. The tab then
offers **Play in Safari Engine**. Choosing it reloads the tab in WebKit and remembers the site
(`SystemEngineSites` in user defaults); page info has **Use Chromium** to undo it. The check
only runs when Chromium can't play H.264, so it does nothing in WebKit or in a codec build.

A tab in WebKit keeps its own cookies (per profile) and runs no Chrome extensions. Video in
iframes from other sites isn't detected yet.

## Building CEF with H.264

```sh
scripts/build-cef.sh          # hours; installs the result into Vendor/cef
xcodegen generate
xcodebuild -scheme EmbarkChromium -configuration Release build
```

The script uses CEF's own `automate-git.py` with
`proprietary_codecs=true ffmpeg_branding=Chrome`, builds the same branch as the current stable
CEF, makes a minimal distribution, and hands it to `fetch-cef.sh` through `CEF_ARCHIVE`.

What it needs:

| | |
|---|---|
| Disk | about 120 GB free (shallow Chromium checkout plus one Release build) |
| RAM | 16 GB minimum, 32 GB+ is much faster |
| Time | roughly 4-10 hours on Apple silicon, longer on Intel |
| Tools | full Xcode selected with `xcode-select`, python3, git, cmake |

It keeps the Mac awake with `caffeinate`. If it stops part way, run it again: the checkout and
build output in `~/cef-build` (or `CEF_WORK_DIR`) are reused. `CEF_NO_UPDATE=1` rebuilds without
fetching anything. The built archive stays in
`~/cef-build/chromium/src/cef/binary_distrib/embark/`, so `CEF_ARCHIVE=<that file>
scripts/fetch-cef.sh` reinstalls it without rebuilding. `CEF_URL=<url>` does the same from a
download, for example a GitHub release asset.

To check it worked, open an `.mp4` H.264 file in Embark, or run
`MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E"')` in the page console; it is
`true` only in the codec build.

CI keeps using the prebuilt CEF. GitHub's hosted macOS runners have neither the disk nor the
time limit for a Chromium build.

## Licensing, before shipping a build to other people

This is not legal advice. It is what to check before Embark publishes binaries with these
codecs.

- **H.264 and AAC are patented.** Patent pools (Via Licensing Alliance, formerly MPEG LA, for
  both AVC/H.264 and AAC) license them per distributed copy. The AVC license has had a free tier
  for the first 100,000 units a year; AAC has an up-front fee. Chrome, Edge, Brave and others
  pay or are covered by these licenses. A free download is still a distributed copy.
- **Building it yourself for your own use** is the common, low-risk case, and is what this
  script is for.
- **Publishing a codec build** (a GitHub release, an auto-update feed) makes the Embark project
  the distributor. Before doing that, either take the pool licenses, or ship without the
  proprietary codecs and rely on macOS: H.264 can decode through Apple's VideoToolbox, which
  Apple licenses, but Chromium's MP4 support and its AAC decoder still come from the codec
  build, so this needs a closer look before relying on it.
- **FFmpeg is LGPL 2.1** inside the Chromium framework. Shipping it is fine as long as the
  source and the build steps stay available, which this repository and `build-cef.sh` cover.
- **Widevine** is separate from all of this and needs Google's approval
  (the application draft is in the project files).
