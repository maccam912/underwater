# Underwater

A single-player maintenance-diving game for Android and desktop, set beside the east jacket of a fictional North Sea oil platform. At 126 metres, you leave Bell 2 alone. Ellis tends your line, Noor supervises from the ship, and Mara takes the relief watch. Each docket takes you between marked work positions along the steel. The helmet view has a CRT filter, and fish move through the light around the jacket.

[Download the latest Android APK](https://github.com/maccam912/underwater/releases/latest/download/Underwater-Android.apk) · [Desktop downloads and checksums](https://github.com/maccam912/underwater/releases/latest) · [Design bible and field research](bible.md)

![Bell 2 suspended beside the Kestrel east jacket](docs/bell-watch.webp)

## Play the first watch

- **Phone.** Swim with your left thumb. Drag open water to look in any direction. Aim up or down as you fin to change depth. When you reach a fixture, touch its hardware to work. You can keep swimming, look over your shoulder or leave the tool at any time.
- **Desktop.** WASD or arrows swim. Mouse looks, Space rises, Q descends and F switches the lamp. Bring the fitting within reach, aim the centre of the helmet and hold the left mouse button to use a tool. Esc pauses.
- **Finding the work.** Use **Call bell** or press E for a clock bearing, height difference and range relative to your current heading. Ellis also gives bearings to Bell 2 when your sheet is ready.
- **A2 wall survey.** Check the gauge on a reference block, prepare marked spots on the jacket leg and seat the probe on clean steel. Lift and re-seat it to verify readings before logging the band. The signed sheet records the locations and measured thicknesses.
- **B4 service-line guides.** Clean the saddle, bring the lined clamp half into position, start the captive fasteners and draw the halves down evenly. Finish with a preset wrench and check the gaps at the two mating edges.
- **The bell.** The two dockets can be taken in either order. Swim back to Bell 2 and hand over. To return with unfinished work, choose **Get a bearing to the bell** in the pause menu and follow the umbilical home. The handover book keeps the actual readings and fitting checks from signed sheets. Finish both dockets to take another watch.
- **The water.** You are alone out there. The jacket groans with the tide, the lamp is old, and the hardline sometimes picks up other voices. Ellis has an ordinary explanation for all of it. Nothing in the water will hurt you. Try switching the lamp off for a while.
- **Saves.** The current watch, work in progress, tool settings, position, samples and signed sheets are stored on the device. Opening the app again offers **Resume watch** when you left the bell.

## Run and build

Install Git LFS before cloning. Run `git lfs pull` in an existing checkout. Open `project.godot` in Godot 4.7, or run `godot --path .`. The project uses the Compatibility renderer. The shipped game plays offline.

```sh
godot --headless --import --path .
godot --headless --fixed-fps 60 --path . --script res://tests/smoke.gd
SHOTS=/tmp/underwater-frames godot --path . --fixed-fps 60 --script res://tests/capture.gd   # windowed playtest frames
```

GitHub Actions tests pushed commits, stamps the Android version, builds signed Android APKs and Linux x64, Windows x64 and universal macOS packages, and publishes them with SHA-256 checksums. The release title gives the workflow run and commit position. The Android APK retains a stable package identity and signing key for in-place updates. The macOS playtest is ad-hoc signed. Release signing credentials are held outside source control.

## Art and audio

The platform, bell, instruments, work orders and story were built for this game. The jacket draws on [underwater survey photographs](docs/underwater-references.md). Original ImageGen materials supply the steel and enamel textures, the oilskin logbook and the bellman’s stained clipboard. The prompts are in [the texture notes](art/materials.md). The offline sound library was generated with ElevenLabs text-to-sound v2. The [authoring script](tools/generate_sfx.py) includes the prompts. Kalam, Barlow, Barlow Condensed and Courier Prime are distributed under their included SIL Open Font Licenses in [ui/fonts](ui/fonts).

This build covers the first repeatable watch. The chamber life and longer mystery in the design bible are proposals for the full game.
