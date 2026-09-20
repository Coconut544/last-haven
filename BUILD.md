# Last Haven - Build Guide

## 1. Verified locally

These were run against Godot **4.7.2 stable** (Linux, headless) while this foundation was built:

```bash
godot --headless --path . --import                     # imports assets, reports script/data errors
godot --headless --path . res://tests/TestRunner.tscn  # full test suite, exit code 0/1
godot --headless --path . --quit-after 180             # boots the real main scene
```

## 2. Local desktop run

Open the project in Godot 4.7.x and press **F5**, or:

```bash
godot --path .
```

## 3. Android export

Godot exports Android builds through the platform's own toolchain. One-time setup:

1. **Install export templates** for your exact Godot version:
   *Editor -> Manage Export Templates -> Download and Install* (or drop
   `Godot_v4.7.2-stable_export_templates.tpz` contents into
   `~/.local/share/godot/export_templates/4.7.2.stable/`).
2. **Install a JDK** (17 is what CI uses) and make sure `java -version` works.
3. **Install the Android SDK** (command line tools are enough) with platform tools, build tools
   and platform 34+. Set `ANDROID_HOME`.
4. **Tell Godot where the SDK is:** *Editor Settings -> Export -> Android -> Android SDK Path*.
   Godot also falls back to the `ANDROID_HOME` environment variable.
5. **Debug keystore:** Godot's default path is `~/.android/debug.keystore` (alias
   `androiddebugkey`, store and key password `android`). Create it if missing:

   ```bash
   keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
     -keystore ~/.android/debug.keystore -storepass android \
     -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkix
   ```

Then either use *Project -> Export -> Android -> Export Project*, or:

```bash
mkdir -p build/android
godot --headless --path . --export-debug "Android" build/android/last-haven.apk
```

`export_presets.cfg` is committed (it contains no secrets) and defines one preset named
**Android**: APK format, arm64-v8a only, package id `com.lasthaven.game`, immersive mode,
landscape orientation.

> **Status:** the Android export has **not been executed yet** - this workspace had no JDK,
> no Android SDK and no export templates. The preset and the CI workflow are written from the
> documented Godot 4 Android process. Treat the first CI run as unverified and fix whatever it
> reports; that is expected work, not a sign the setup is wrong.

## 4. Continuous integration

| Workflow | Trigger | Does |
| --- | --- | --- |
| `.github/workflows/validate.yml` | push to `main`, PRs, manual | installs Godot 4.7.2, imports the project, runs the test suite (fails on `SCRIPT ERROR` or a failing check), boots the game for 180 frames, uploads logs |
| `.github/workflows/android-build.yml` | manual, `v*` tags | installs JDK 17 + Android SDK + Godot + export templates, generates a debug keystore, exports a debug APK, uploads it as an artifact |

The validate workflow is the gate: it fails when the real build or the real tests fail. Nothing
in CI suppresses errors or fakes a successful build.

## 5. Signing and secrets policy

- **Never commit** keystores, `*.jks`, `export_credentials.cfg` or passwords. They are ignored
  by `.gitignore`.
- Debug builds use the standard Android debug keystore, generated inside CI for each run.
- **Release signing** (Play Store upload key, versioning, tracks) is deliberately not configured
  yet. When it is: store the keystore and passwords as GitHub Actions secrets, inject them at
  build time only, and document the rotation process here.

## 6. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `Cannot open file 'res://scenes/main/Main.tscn'` during import | A scene referenced by `project.godot` is missing or renamed. Fix the path. |
| `libfontconfig.so.1: cannot open shared object file` (headless Linux container) | Host libraries missing for the editor binary. Harmless for headless testing; install `fontconfig` if fonts matter. |
| Blank or half-styled game | A scene failed to load: run the test suite, it fails loudly on load errors. |
| `Could not find type <ClassName>` after adding a script | The class cache is stale: run `godot --headless --path . --import`. |
| Export fails with "Android SDK path not set" | Set *Editor Settings -> Export -> Android -> Android SDK Path* or `ANDROID_HOME`. |
| Export fails with "No export template found" | Install export templates for the exact Godot version (4.7.2). |
| Export fails on signing | The debug keystore is missing at `~/.android/debug.keystore`. |
| Test suite fails on a data problem | `ItemDatabase` logs the file and the problem; fix the `.tres`, not the check. |

## 7. Version pinning

`GODOT_VERSION` is set in both workflows and the project's `config/features` is
`PackedStringArray("4.7", "Mobile")`. Bumping the engine version means: update both workflows,
re-run `--import`, run the test suite, and note the change in `AI_HANDOFF.md`.
