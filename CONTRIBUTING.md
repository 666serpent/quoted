# Contributing

Bug reports and focused pull requests are welcome. Keep the reader quiet: controls belong in the app menu or credits panel, and scrolling should stay under the reader's control.

## Development

Use macOS 26 or later with Swift 6.2+ and a macOS 26+ SDK. Xcode or Command Line Tools are supported. There are no third-party Swift package dependencies.

```sh
./scripts/test.sh
./scripts/build.sh
open dist/Quoted.app
```

The normal test suite uses fixtures and does not require Spotify, credentials, or network access. An optional provider integration check is available:

```sh
QUOTED_LIVE_TEST=1 ./scripts/test.sh --filter LiveServiceTests
```

For UI changes, check both glass appearances, the smallest supported window, scrolling, dragging, and the credits panel. You can prepare separate offline preview apps without touching the main app's preferences:

```sh
./scripts/prepare-screenshots.sh
open .build-docs/Quoted-dark.app
open .build-docs/Quoted-light.app
open .build-docs/Quoted-credits.app
```

Preview text and credit names are demonstration content, not a listener's song data. Please keep screenshots free of private information and third-party lyric text. `./scripts/export-screenshots.sh` exports the three native preview windows directly into `docs/images/` without capturing the desktop.

## Releases

1. Update the version in `Resources/Info.plist` and `CHANGELOG.md`.
2. Run the tests and `./scripts/package.sh` on the target architecture.
3. Verify the app and archive, then attach the ZIP and `SHA256SUMS` to a GitHub release.

`package.sh` produces a locally signed build. Developer ID signing and Apple notarization require the maintainer's own certificates and are not part of the default build.

## Icon

`Resources/AppIcon.icon` holds the original vector mark and appearance settings. `Resources/Assets.car` is the compiled native catalog, so normal builds do not need an icon compiler. To rebuild the catalog:

```sh
./scripts/compile-icon.sh
```

Use Xcode's `actool`, or set `QUOTED_ACTOOL` to a compatible compiler. The checked-in catalog was generated with [viraptor/actool](https://github.com/viraptor/actool) 2.2.4 and validated with macOS IconServices.

The stable bundle identifier and window autosave key preserve preferences and Spotify Automation access for earlier installations; keep them unchanged when renaming internal code.
