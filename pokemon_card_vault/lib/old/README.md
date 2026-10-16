# Previous application reference

On the `AppMobile` branch, the previous application folders are archived here
as reference for the active implementation in `lib/rebuild/`.

The original `constants`, `models`, `providers`, `scan_v2`, `screens`, `services`,
`utils`, `wallet` and `widgets` folders keep their internal layout and contents.
Their tests and tools now import `lib/old/...`.

`lib/main.dart` remains the previous application's entry point and imports this
archive. `lib/firebase_options.dart` stays shared at the root of `lib` because
Rebuild uses it as well.

Run the current mobile application with:

```sh
flutter run --target lib/rebuild/main_mobile_prototype.dart
```
