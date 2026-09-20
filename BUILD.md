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

The toolchain below is the one that produced a working APK. All versions are pinned in
`.github/workflows/android-build.yml`; they have to agree with each other.

1. **Export templates for the exact Godot version.** *Editor -> Manage Export Templates ->
   Download and Install*, or unpack `Godot_v4.7.2-stable_export_templates.tpz` into
   `~/.local/share/godot/export_templates/4.7.2.stable/`. Godot recognises a template set by the
   `version.txt` inside it. Android only needs `android_debug.apk`, `android_release.apk`,
   `android_source.zip` and `version.txt`, so extracting just those is enough (that is what CI
   does; it avoids unpacking ~1 GB of unrelated platform templates).
2. **JDK 17** (Temurin). The export shells out to `apksigner`, which is a Java tool, so a JDK is
   mandatory - not just for the SDK tools.
3. **Android SDK** with `platform-tools`, `build-tools;36.0.0` and `platforms;android-36`:

   ```bash
   sdkmanager "platform-tools" "build-tools;36.0.0" "platforms;android-36"
   ```

   The build-tools version must match the export template's target API level (36 for Godot
   4.7.2, which also sets `minSdkVersion 24`). If no build-tools match, Godot warns and falls
   back to the newest it finds - it works, but CI pins the matching version on purpose.
4. **Debug keystore.** Debug builds are signed with the well-known Android debug key (alias
   `androiddebugkey`, password `android`). Create it if it does not exist:

   ```bash
   mkdir -p ~/.android
   keytool -genkeypair -keyalg RSA -keysize 2048 -validity 9999 \
     -alias androiddebugkey -keypass android \
     -keystore ~/.android/debug.keystore -storepass android -storetype PKCS12 \
     -dname "CN=Android Debug,O=Android,C=US"
   ```

   `keytool` will not create the parent directory, and JDK 17 no longer knows the `pkix` store
   type (`-deststoretype pkix` fails with `PKIX not found`). PKCS12 is the default and
   `apksigner` reads it.
5. **Point Godot at the toolchain.** In the editor: *Editor Settings -> Export -> Android*, then
   set **Android SDK Path**, **Java SDK Path** and the debug keystore. For headless/CI use, the
   same values live in `~/.config/godot/editor_settings-<major>.<minor>.tres`; for 4.7.2 the
   file is **`editor_settings-4.7.tres`** (the name carries the engine's major.minor, so it
   changes when the engine is upgraded, and a wrongly named file is silently ignored):

   ```
   [gd_resource type="EditorSettings" format=3]

   [resource]
   export/android/android_sdk_path = "/path/to/android-sdk"
   export/android/java_sdk_path = "/path/to/jdk-17"
   export/android/debug_keystore = "/home/you/.android/debug.keystore"
   export/android/debug_keystore_user = "androiddebugkey"
   export/android/debug_keystore_pass = "android"
   ```

Then either use *Project -> Export -> Android -> Export Project*, or:

```bash
mkdir -p build/android
godot --headless --path . --import
godot --headless --path . --export-debug "Android" build/android/last-haven.apk
```

The export writes `build/android/last-haven.apk` (ignored by git) and signs it. Android export
requires `rendering/textures/vram_compression/import_etc2_astc=true` in `project.godot`; without
it every export fails with *"ETC2/ASTC texture compression is required for Android export"*.

`export_presets.cfg` is committed (it contains no secrets) and defines one preset named
**Android**: APK format, arm64-v8a only, package id `com.lasthaven.game`, immersive mode,
landscape orientation, `package/signed=true`.

> **Status:** verified. This exact configuration produced a 28,656,730-byte signed debug APK
> both locally (Godot 4.7.2 + build-tools 36.0.0) and in GitHub Actions run
> [35508726118](https://github.com/Coconut544/last-haven/actions/runs/35508726118).

## 4. Continuous integration

| Workflow | Trigger | Does |
| --- | --- | --- |
| `.github/workflows/validate.yml` | push to `main`, PRs, manual | installs Godot 4.7.2, imports the project, runs the test suite (fails on `SCRIPT ERROR` or a failing check), boots the game for 180 frames, uploads logs |
| `.github/workflows/android-build.yml` | push to `main`, PRs to `main`, `v*` tags, manual | installs JDK 17 + the pinned Android SDK packages + Godot + export templates, generates a debug keystore, exports a debug APK, **validates** it, uploads it as `last-haven-debug-apk` |

Neither workflow suppresses errors or fakes a successful build. `continue-on-error` is not used
anywhere. The Android job fails if the APK is missing, under 10 MB, has the wrong application id
or no `libgodot_android.so` / `assets/assets.sparsepck`, or if `apksigner verify` rejects it -
so a green Android build always means a real, installable artifact. The job also uploads
`build/android/apk-validation.txt` and `build/android/export.log` next to the APK.

> Note: the Android job runs on pushes to `main` and on PRs targeting `main`. Triggering it with
> `gh workflow run` requires the `actions: write` permission, which the managed integration does
> not have (`HTTP 403`); use a push, or the Actions tab, instead.

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
| Export fails with "Android SDK path not set" | Set *Editor Settings -> Export -> Android -> Android SDK Path*, or write the correct `editor_settings-<major>.<minor>.tres` (see section 3.5). |
| Export fails with "A valid Java SDK path is required in Editor Settings" | Set *Editor Settings -> Export -> Android -> Java SDK Path* (key `export/android/java_sdk_path`). |
| Export fails with "ETC2/ASTC texture compression is required for Android export" | Enable *Import ETC2 ASTC* (the `import_etc2_astc` setting in section 3) and re-import. |
| Export warns "Could not find version of build tools that matches Target SDK, using X" | Install the build-tools version matching the template's target API level (`build-tools;36.0.0` for Godot 4.7.2). |
| Export fails with "No export template found" | Install export templates for the exact Godot version (4.7.2) - check `~/.local/share/godot/export_templates/4.7.2.stable/version.txt` exists. |
| Export fails on signing, or the APK is unexpectedly unsigned | The debug keystore is missing or was never created: see section 3.4. Godot silently generates its own debug keystore only when the configured path does not exist. |
| CI fails in a `setup-android` step with `Failed to find package 'tools'` | The legacy `tools` SDK package no longer exists. Do not request it; the workflow installs only `platform-tools`, `build-tools;<ver>` and `platforms;android-<ver>`. |
| Test suite fails on a data problem | `ItemDatabase` logs the file and the problem; fix the `.tres`, not the check. |

## 7. Version pinning

`GODOT_VERSION` is set in both workflows and the project's `config/features` is
`PackedStringArray("4.7", "Mobile")`. Bumping the engine version means: update both workflows,
re-run `--import`, run the test suite, and note the change in `AI_HANDOFF.md`.

The Android job additionally pins `JDK_VERSION`, `ANDROID_BUILD_TOOLS` and `ANDROID_PLATFORM`.
They are not independent: the official export template for a given Godot version declares its own
`minSdkVersion`/`targetSdkVersion` (4.7.2 -> 24/36), and `ANDROID_BUILD_TOOLS`/`ANDROID_PLATFORM`
should match that target API level. Check a new engine version with:

```bash
apkanalyzer manifest target-sdk <export_templates>/android_debug.apk
```
