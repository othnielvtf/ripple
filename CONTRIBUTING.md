# Contributing to Ripple

Thanks for helping make a small Mac audio player better. Keep changes focused, preserve native keyboard and accessibility behaviour, and avoid adding background work to idle playback.

## Development

Open `Package.swift` in Xcode, or run `./Scripts/build.sh` to create `dist/Ripple.app`. No third-party dependencies are required.

| File | Responsibility |
| --- | --- |
| `App.swift` | App lifecycle, menus, Finder file opening |
| `PlaybackController.swift` | AVAudioPlayer, queue, seeking, playback state |
| `PlayerWindow.swift` | Main AppKit interface and drag and drop |
| `Appearance.swift` | Themes, appearance, saved settings |
| `EffectSlider.swift` | Custom rendering on native NSSlider controls |
| `SettingsWindow.swift` | Appearance and file-association settings |
| `FileAssociations.swift` | Default-app integration and result verification |

## Before opening a pull request

Build the universal app and run `./Scripts/test.sh` on a Mac with an audio output. An optional MP3 path adds decoding and seeking checks. The tests use silent audio and isolated preferences, and do not change your default audio apps.

For interface changes, check Dark and Light appearance, keyboard operation, a short volume slider, and a wide progress slider. Include a screenshot when it helps explain the change. The project’s screenshot helper can render the actual interface using generated demo files:

```sh
./Scripts/capture-screenshots.sh
```

Describe the problem, the resulting behaviour, and what you checked in your pull request. For a bug report, include your Ripple version, macOS version, CPU architecture, and clear reproduction steps. Avoid attaching private audio files; a small generated sample is preferable.

## Releases

Update the version in `Resources/Info.plist` and the About panel in `App.swift`. Run `./Scripts/package-release.sh VERSION`, inspect the result, and publish a GitHub release for the matching `vVERSION` tag. The release workflow attaches a universal ZIP and `SHA256SUMS`.

The current build uses an ad hoc signature. Developer ID signing and notarization require the maintainer’s Apple credentials and are not part of the public build scripts.
