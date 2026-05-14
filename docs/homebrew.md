# Homebrew

Use the private tap for normal installs:

```sh
brew tap mkusaka/tap
brew install mkusaka/tap/pbm
pbm --version
pbm doctor
```

Until the first tagged release has completed, install from source with `HEAD`:

```sh
brew install --HEAD mkusaka/tap/pbm
```

## Bottles

Tagged releases publish Homebrew bottles for:

- macOS Sequoia 15, Apple Silicon: `arm64_sequoia`
- macOS Sequoia 15, Intel: `sequoia`
- macOS Tahoe 26, Apple Silicon: `arm64_tahoe`
- macOS Tahoe 26, Intel: `tahoe`

The bottle flow is:

1. Push a `vMAJOR.MINOR.PATCH` tag that matches `pbmVersion` in `macos/Sources/PBMCore/Contract.swift`.
2. `.github/workflows/release.yml` runs the normal CI workflow.
3. The workflow creates a draft GitHub Release and computes the tagged source archive SHA-256.
4. macOS runners build and upload Homebrew bottle assets to that release.
5. The workflow publishes the release.
6. The workflow dispatches `mkusaka/homebrew-tap` to update `Formula/pbm.rb` with the source SHA and bottle SHA values.

The upstream repository needs a `HOMEBREW_TAP_TOKEN` secret that can dispatch `mkusaka/homebrew-tap`.

## Source Builds

If a bottle does not match the user's system, Homebrew falls back to building from source. Source builds require Xcode with Swift 6.2 because the package uses `swift-tools-version: 6.2` and macOS 15 APIs.

## Local Checks

From this repository:

```sh
swift build --configuration release
PBM_BIN="$(swift build --show-bin-path)/pbm" swift test
scripts/e2e-smoke.sh
mise exec -- actionlint
mise exec -- zizmor --offline .
mise exec -- ghalint run
mise exec -- pinact run --check
```

From `mkusaka/homebrew-tap`:

```sh
ruby -c Formula/pbm.rb
brew readall --os=sequoia --arch=all mkusaka/tap
brew readall --os=tahoe --arch=all mkusaka/tap
```
