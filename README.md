# Underwater

A single-player maintenance-diving game for Android and desktop, set beside the east jacket of a fictional North Sea oil platform. Start in Bell 2 at 126 metres. Take a work docket, find the marked steel, brace against the fixture, and bring a reading or a fitted carrier back for the next diver.

[Download the latest Android APK](https://github.com/maccam912/underwater/releases/latest/download/Underwater-Android.apk) · [Desktop downloads and checksums](https://github.com/maccam912/underwater/releases/latest) · [Design bible and field research](bible.md)

![Bell 2 suspended beside the Kestrel east jacket](docs/bell-watch.webp)

## Play the first watch

- **Phone.** Hold and slide your left thumb to swim. Drag on the right to look. The direction you look sets the direction you fin, including up and down. Tap **Bearing** to face the worksite or the bell. Close to the fixture, the same button becomes **Brace**. Use the tool with taps, then swim home and tap **File sheet**.
- **Desktop.** WASD or arrows swim. Mouse looks. Space rises, Q descends, E takes a bearing or interacts, and Esc pauses. Click the instrument controls or use left/right to adjust the echo gate or left clamp shoe, up/down for the right shoe, Enter to submit and Esc to unbrace.
- **The bell.** The two dockets can be taken in either order. A rejected reading leaves the tool in your hands. Pause and choose **Follow line back to bell** for a tended return. Finish both dockets to start another watch with fresh readings. The handover book carries the latest signed entries and a note from Mara.
- **Saves.** The current watch, tool settings, position, samples and signed sheets are stored on the device. Opening the app again offers **Resume watch** when you left the bell.

## Run and build

Install Git LFS before cloning. Run `git lfs pull` in an existing checkout. Open `project.godot` in Godot 4.7, or run `godot --path .`. The project uses the Compatibility renderer. The shipped game plays offline.

```sh
godot --headless --import --path .
godot --headless --fixed-fps 60 --path . --script res://tests/smoke.gd
```

GitHub Actions tests pushed commits, stamps the Android version, builds signed Android APKs and Linux x64, Windows x64 and universal macOS packages, and publishes them with SHA-256 checksums. The release title gives the workflow run and commit position. The Android APK retains a stable package identity and signing key for in-place updates. The macOS playtest is ad-hoc signed. Release signing credentials are held outside source control.

## Art and audio

The platform, bell, instruments, work orders and story were built for this game. Two original ImageGen albedo textures supply the surface of the steel jacket and the yellow bell enamel. The exact prompts are in [the texture notes](art/materials.md). The offline sound library was generated with ElevenLabs text-to-sound v2. The [authoring script](tools/generate_sfx.py) includes the prompts. Barlow, Barlow Condensed and Courier Prime are distributed under their included SIL Open Font Licenses in [ui/fonts](ui/fonts).

This build covers the first repeatable watch. The chamber life and longer mystery in the design bible are proposals for the full game.
