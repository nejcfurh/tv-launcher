# TV Launcher

A minimal, Apple TV-style home screen for Android TV and Google TV, built on top of
**[Arc Launcher](https://github.com/meddouribadis/arclauncher)** by
[meddouribadis](https://github.com/meddouribadis).

The goal is a quiet home screen: one row of the apps you actually use, a full-screen
"Watch Next" banner above it, and nothing else. No ads, no recommendations rows, no
store tiles.

> TV Launcher is a fork. Almost everything that makes it work — the Watch Next
> integration, the dock, wallpapers, settings and the overall architecture — comes from
> Arc Launcher and the projects it is based on. See [Credits](#credits).

## What is different from Arc Launcher

### Home screen

- **Single dock row** anchored to the bottom of the screen, with as many apps as you
  add. Arc shows at most six apps in a row; TV Launcher widens the row instead of
  dropping apps.
- **Immersive Watch Next banner** with a source badge that reads
  `WATCH NEXT ON <logo>`. Netflix, HBO, YouTube, Apple TV and SkyShowtime use bundled
  white logos; other apps use the foreground layer of their own icon, drawn in white.
  If an app has neither, the badge shows its name.
- **Top bar shortcuts** next to Settings and Wi-Fi: Play Store, a browser
  ([TV Bro](https://github.com/truefedex/tv-bro), falling back to the TV's built-in
  browser) and [VLC](https://www.videolan.org/vlc/download-android.html) for network
  drives. Each shortcut only appears when its app is installed.
- **Full European date** in the top bar, e.g. `Tuesday, 17.11.2026`.

### Tiles

- **Custom app names**: hold OK on a tile → *Rename*. Leave the field empty to use the
  app's own name again.
- **Show the name of the selected app only**, like Apple TV, so labels don't crowd the
  row (Settings → Interface → Miscellaneous).
- **Tile corner radius**: 6, 12, 20 or 28 dp (Settings → Interface → Appearance).

### Speed and Home button

- **Apps open on the key press.** Arc waited for the press animation and a database
  write before starting the app (~170 ms); TV Launcher starts it immediately (~20 ms).
- **Home button service.** Google TV sends the remote's Home button to its own launcher
  even when another app is the default home app. An accessibility service replaces the
  stock home screen with TV Launcher whenever it appears, including after a reboot.

### Other

- New app ID `local.tvlauncher`, so it installs next to Arc Launcher.
- "Created by" footer in the settings menu.

## Building

Requirements:

- Flutter 3.41 (stable)
- JDK 17 (Gradle 8.13 does not run on newer JDKs)
- Android SDK with build-tools 36

```bash
flutter config --jdk-dir /path/to/jdk-17
flutter pub get
flutter test
flutter build apk --release --flavor github --split-per-abi
```

Most Google TV sets run a 32-bit userspace even on 64-bit chips. Check with
`adb shell getprop ro.product.cpu.abilist` and install the matching APK
(`app-armeabi-v7a-github-release.apk` or `app-arm64-v8a-github-release.apk`) from
`build/app/outputs/flutter-apk/`.

### Signing

Release builds are signed with the key named in `android/local.properties`, which is
git-ignored:

```properties
storeFile=/absolute/path/to/your.keystore
storePassword=...
keyAlias=...
keyPassword=...
```

Keep the keystore safe: Android only installs an update over an existing install if
it is signed with the same key.

## Installing and setting as Home

Enable wireless debugging on the TV (Settings → System → Developer options; the TV
must be on Wi-Fi), pair with `adb pair <ip>:<port>`, then:

```bash
adb install -r app-armeabi-v7a-github-release.apk
```

Let the Watch Next banner read what you are watching:

```bash
adb shell pm grant local.tvlauncher com.android.providers.tv.permission.READ_EPG_DATA
```

Make it the home app:

```bash
adb shell cmd package set-home-activity local.tvlauncher/com.omeda.arc.MainActivity
```

On Google TV that alone is not enough — Home still opens the stock launcher. Turn on
the Home button service:

```bash
adb shell settings put secure enabled_accessibility_services local.tvlauncher/com.omeda.arc.HomeButtonService
```

```bash
adb shell settings put secure accessibility_enabled 1
```

TCL TVs also block background services of sideloaded apps. If Home still opens the
stock launcher, allow TV Launcher to start in the background, then turn the service
off and on again:

```bash
adb shell appops set local.tvlauncher AUTO_START allow
```

```bash
adb shell appops set local.tvlauncher ACCESS_RESTRICTED_SETTINGS allow
```

To undo everything, point the home app back at the stock launcher and clear the
accessibility service:

```bash
adb shell cmd package set-home-activity com.google.android.apps.tv.launcherx/.home.HomeActivity
```

```bash
adb shell settings put secure enabled_accessibility_services null
```

Tested on a TCL Google TV (Android 14).

## Trademarks

Netflix, HBO, YouTube, Apple TV, SkyShowtime, Disney+ and other names and logos shown
in the Watch Next badge are trademarks of their respective owners. They are included
only to identify which app a show comes from. This project is not affiliated with or
endorsed by any of them.

## License

GPL-3.0, the same as Arc Launcher and FLauncher. See [LICENSE](LICENSE).

## Credits

TV Launcher stands on a chain of open-source launchers:

- **[Arc Launcher](https://github.com/meddouribadis/arclauncher)** by
  [meddouribadis](https://github.com/meddouribadis) — the direct base of this project.
  If you like TV Launcher, consider
  [supporting Arc Launcher's development](https://github.com/sponsors/meddouribadis).
- **[LTvLauncher](https://github.com/LeanBitLab/LtvLauncher)** by
  [LeanBitLab](https://github.com/LeanBitLab) — the base of Arc Launcher.
- **[FLauncher (fork)](https://github.com/osrosal/flauncher)** by
  [osrosal](https://github.com/osrosal) — community fork with additional features.
- **[FLauncher](https://gitlab.com/flauncher/flauncher)** by
  [etienn01](https://github.com/etienn01) — the original project.

The HBO, YouTube and Apple TV logo shapes come from [Simple Icons](https://simpleicons.org)
(CC0). The VLC cone in the top bar is based on Simple Icons' VLC shape.

TV Launcher changes by [Nejc Furh](https://nejcfurh.dev).
