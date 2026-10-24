# Contributing to Embark

Thanks for helping. Embark is an early, native macOS browser, so small focused pull requests
are the easiest to review and merge.

## Before you start

- For a bug fix or a small polish, open a pull request directly.
- For a new feature or a change to how something behaves, open an issue first so we can agree
  on the direction before you write code.
- Look at [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the app is put together.

## Setting up

You need macOS 26, Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Embark.xcodeproj
```

The `Embark` scheme uses WebKit and needs no downloads, which is the quickest way to work on
the UI. To work on the Chromium engine, run `scripts/fetch-cef.sh` (needs `cmake`) and build
the `EmbarkChromium` scheme.

You don't need an Apple developer account. Xcode signs local builds ad hoc. If the Chromium
build keeps asking for the "Embark Safe Storage" keychain item after each rebuild, sign it
with `scripts/sign-local.sh path/to/Embark.app`, which creates a self-signed identity on your
own Mac (see the README).

`Embark.xcodeproj` is generated from `project.yml` and is not committed. Change `project.yml`
instead, and run `xcodegen generate` again.

## Making a change

1. Fork the repo and create a branch from `main`.
2. Keep the change to one thing. Match the style of the code around it.
3. Run the tests:

   ```sh
   xcodebuild test -project Embark.xcodeproj -scheme EmbarkTests -destination 'platform=macOS'
   ```

   Model logic (spaces, favorites, folders) should come with a test in `Tests/`.
4. Check both engines still build. CI builds WebKit and Chromium on every pull request, so it
   is fine to let CI check the Chromium build if you only touched UI code.
5. For UI changes, add a screenshot or short recording to the pull request.

## Pull requests

- Describe what changed and why, and how you tested it.
- CI must pass before a pull request is merged.
- By contributing, you agree that your work is released under the [MIT License](LICENSE).

## Reporting bugs and security issues

Open a bug report with the issue template. For anything that could put users at risk, follow
[SECURITY.md](SECURITY.md) instead of opening a public issue.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
