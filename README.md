# Underwater

A single-player maintenance-diving game for Android and desktop, set beside the east jacket of a fictional North Sea oil platform. Start in Bell 2 at 126 metres. Take a work docket, find the marked steel, brace against the fixture, and bring a reading or a fitted carrier back for the next diver.

[Download the latest Android APK](https://github.com/maccam912/underwater/releases/latest/download/Underwater-Android.apk) · [Desktop downloads and checksums](https://github.com/maccam912/underwater/releases/latest) · [Design bible and field research](bible.md)

![Bell 2 suspended beside the Kestrel east jacket](docs/bell-watch.webp)

## Play the first watch

- **Phone.** Swim with the left thumb and look with the right. Look up or down as you fin to change depth. Touch the lamp icon to switch the helmet beam. **Call bell** faces you toward the work or home. Swim up to the tagged fixture, touch **Brace**, then work directly on the hardware. **Let go** releases your grip.
- **Desktop.** WASD or arrows swim. Mouse looks. Space rises, Q descends, F switches the lamp, E calls the bell or braces. Point and drag to work. Right-drag moves your head while braced. E or Esc lets go, Esc during the swim pauses.
- **A2 wall survey.** Put the cabled probe on the bare round patch. Drag the gate on the meter glass to the first strong reflection after the initial pulse. Press the red MARK button on the meter. With a keyboard, Space plants the probe, left/right turn the dial, and Enter records.
- **B4 survey clamp.** Drag each shoe up or down until its nick meets the fixed brass mark, then throw the central latch. Left/right adjust the left shoe, up/down adjust the right, and Enter throws the latch. A proud foot can be reset in place.
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

The platform, bell, instruments, work orders and story were built for this game. The jacket draws on [underwater survey photographs](docs/underwater-references.md). Original ImageGen materials supply the steel and enamel textures, the oilskin logbook and the bellman’s stained clipboard. The prompts are in [the texture notes](art/materials.md). The offline sound library was generated with ElevenLabs text-to-sound v2. The [authoring script](tools/generate_sfx.py) includes the prompts. Kalam, Barlow, Barlow Condensed and Courier Prime are distributed under their included SIL Open Font Licenses in [ui/fonts](ui/fonts).

This build covers the first repeatable watch. The chamber life and longer mystery in the design bible are proposals for the full game.
