# Releases and automatic updates

Embark updates itself with [Sparkle](https://sparkle-project.org). Each GitHub release carries
the app as `Embark-<version>.zip` and an `appcast.xml` describing it. Installed copies read
`releases/latest/download/appcast.xml` once a day, download a newer version in the background,
and install it the next time Embark quits (or right away from Settings ▸ Updates). Embark ▸
Check for Updates… checks on demand.

Every update is signed with an EdDSA key. The app carries the public half (`SPARKLE_PUBLIC_KEY`
in `project.yml`) and refuses any update the private half didn't sign. Builds without a public
key, such as a fresh clone built in Xcode, leave the updater off.

## One-time setup

On the Mac that signs Embark, with `gh` signed in:

```sh
scripts/sign-local.sh path/to/Embark.app   # only if you have never run it on this Mac
scripts/setup-updates.sh
git commit -am "Add the update public key" && git push
```

`setup-updates.sh` creates the update key in your login keychain, saves three repository
secrets the release workflow needs, and writes the public key into `project.yml`:

| Secret | What it is |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | Private EdDSA key that signs each update |
| `EMBARK_SIGNING_P12` | The "Embark Local Dev" code signing identity, base64 |
| `EMBARK_SIGNING_P12_PASSWORD` | Password for that identity file |

Back up the private key (Keychain Access, item "Private key for signing Sparkle updates",
account `dev.embark.browser`). If it is lost, installed copies can't accept new updates and
everyone has to download Embark again by hand.

## Publishing a release

Push a tag, or run the **Release** workflow from the Actions tab with a version:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

The workflow builds the Chromium app in Release for Apple silicon, signs it with the identity
from the secrets, zips it, signs the zip for Sparkle, and publishes the release with the zip and
`appcast.xml`. The version is the tag; the build number is the commit count on that commit, so
it always increases along `main`.

## Signing, Gatekeeper and what users see

Embark isn't signed with an Apple Developer ID or notarized, which needs a paid Apple Developer
account. It is signed with a self-signed certificate ("Embark Local Dev"). What that means:

- **First install:** macOS blocks the downloaded app the first time ("Apple could not verify
  Embark is free of malware"). Open System Settings ▸ Privacy & Security, scroll to Security,
  and click **Open Anyway**. Or remove the download flag in Terminal:
  `xattr -dr com.apple.quarantine /Applications/Embark.app`. This happens once.
- **Updates:** Sparkle checks the EdDSA signature, then that the new app is signed by the same
  certificate as the installed one, and clears the download flag before installing. So updates
  install without any Gatekeeper prompt.
- **Keychain:** because every release has the same signing identity as the copy you built and
  signed with `scripts/sign-local.sh`, macOS keeps the "Always Allow" given to "Embark Safe
  Storage" across updates.
- **Intel Macs:** releases are built for Apple silicon only, and the appcast says so, so Intel
  Macs aren't offered them.

With a Developer ID later, sign with it in `scripts/sign-local.sh`, add notarization to the
release workflow, and the first-launch prompt goes away. The update key stays the same.
