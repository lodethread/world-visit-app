# world-visit-app

## Launcher icons

Launcher icons are generated during CI (and ignored in git). To build locally, run:

```sh
flutter pub get
./tool/icon/materialize_icon.sh
```

This decodes `tool/icon/source.png.b64` into a PNG and runs `flutter_launcher_icons`
with `flutter_launcher_icons.yaml` to produce platform-specific icons (not committed).
