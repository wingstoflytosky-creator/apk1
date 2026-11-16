# Neon Strike 3D v1.1 — Native Android shooter

A Godot 4.3 first-person Android arena shooter with 3D assets supplied by the project owner. This is a playable **prototype**, not a polished commercial shooter, and the Android build has **not** been verified on an actual device.

## What's playable

- First-person shooter with 3D ground arena and obstacles.
- Textured GLB soldier enemies, optional FBX drone enemies from wave 2 onward.
- Optional FBX AK-74 visible in first-person; if the import fails, a procedural rifle appears.
- Hit detection, shooting effect, enemy waves, drone movement, enemy damage, health, 30-round magazine and reload.
- Collectible ammo (yellow) and health (green) boxes from defeated bots.
- Mobile landscape screen, drag-to-move (left) and drag-to-aim (right), FIRE and RELOAD buttons.
- Desktop test: WASD/arrows, right-mouse drag to aim, left-click/space to shoot.

## Build an APK with GitHub Actions — no Android Studio required on your computer

1. Extract the downloaded project ZIP.
2. Visit https://github.com/new and create a repo (e.g. `neon-strike-mobile`).
3. Upload the **contents** of the `NeonStrike3D_Assets_v1_1` folder into the repo's **root**. Make sure `.github/workflows/android-apk.yml` is also present. Upload the contents, **not the ZIP**.
4. Commit the uploaded files to the repository's `main` branch.
5. In the repo go to **Actions** > **Build Android APK** > **Run workflow**. (If GitHub offers to enable Actions, enable it.)
6. When the workflow succeeds, open the run and download the `NeonStrike-Android-APK` artifact. This downloaded artifact is itself a ZIP, so extract it.
7. Send `NeonStrike-debug.apk` to your Android phone, and install it after allowing installations from that source in Android settings.

The debug APK will be signed with a throwaway debug key generated on the GitHub runner. It is for installing/testing, **not** for distribution or Play Store submission. Because each build uses a new debug key, uninstall an older test version before installing a freshly built one if Android reports incompatible signatures. The APK is built for **arm64-v8a only** (common modern Android phones).

### Local preview/editing

Open `project.godot` using **Godot Engine 4.3** or a compatible 4.x version. Let it import assets. Press F5 to run on desktop. In an environment without a graphics engine and Android SDK, the project can be prepared but an APK cannot be built or tested locally.

## Included 3D assets

| Path | Role | Import |
|---|---|---|
| `assets/soldier.glb` | Enemies | Godot-native glTF 2.0 import; contained texture |
| `assets/AK-74_pack.fbx` | Rifle viewmodel | Godot 4.3 ufbx importer; texture references may require the original texture PNG files |
| `assets/drone.fbx` | Aerial bot | Godot 4.3 ufbx importer; may need scale/material tuning |

Materials and orientations in FBX imports have not been visually verified. Geometry may render without its original textures if textures were not embedded. See `ASSET_NOTES.md` for other upload formats.

## Troubleshooting

- **No GitHub workflow showing**: upload the hidden `.github/workflows/android-apk.yml` file in the repository root, and ensure Actions are enabled.
- **FBX import error**: move the troublesome FBX out of `assets` and remove it from the project; the script has procedural geometry fallbacks, but change `const RIFLE_PATH` or `const DRONE_PATH` if needed. Capture the full workflow logs for diagnosis.
- **Godot errors**: open Actions > latest failed run > the red step and copy the error lines. Each project and engine version has nuances and this package has not been compiled here.
- **Android says app not installed**: uninstall the old debug version first; each GitHub build uses a different signing key.
- **Phone performance**: reduce `range(min(3 + wave * 2, 18))` in `scripts/game.gd`, shrink textures/meshes, or turn off the drone model to improve frame rate.

## Licenses

The game code is new project code. The 3D models are user-supplied; verify that their respective model and texture licenses permit redistribution before publishing this repository publicly or distributing an APK. No third-party asset license was provided in this upload and no license is asserted here.
