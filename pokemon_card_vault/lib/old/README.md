# Previous application reference

On the `AppMobile` branch, the previous application is archived here as
reference for the active implementation in `lib/rebuild/`.

The previous application's entry point is `lib/old/main.dart`. Its `constants`,
`models`, `providers`, `scan_v2`, `screens`, `services`, `utils`, `wallet` and
`widgets` folders retain their internal layout. Legacy tests and tools use
`lib/old/...` paths.

`lib/firebase_options.dart` stays shared at the root of `lib` because Rebuild
uses it as well. There is no default `lib/main.dart` on this mobile branch;
choose the target explicitly.

Run the current mobile application:

```sh
flutter run --target lib/rebuild/main_mobile_prototype.dart
```

Run the previous application:

```sh
flutter run --target lib/old/main.dart
```
