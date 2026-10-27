## 0.2.0

- The panel's storage is kept by the app (D372): the guest a tester declared, the notices they
  dismissed and their filters survive the app being killed, relaunched or updated, which Android's
  web view storage didn't. The panel token stays in the web view.
- `Viper.open()` and `Viper.show()` in `markers.dart`: the app opens Viper, or brings back a hidden
  launcher, from its own trigger (a menu row, a logo long press, a deep link). `Viper.start` takes
  `revealHint`, the words a tester reads when hiding Viper; with it, Hide Viper is offered without
  a shake (D371).
- The `VIPER_COMMIT` define: the commit CI built from goes in the environment's `app.commit` and
  every screen reference, so Viper can tell whether a tester has a fix (D356, D357).
- The panel's sheet keeps its footer above the home indicator or gesture bar: a strip in the
  sheet's color takes the bottom safe area, and goes when the keyboard is up.

## 0.1.0

- `Viper.start`, the config call and the OS floor (iOS 16.4, Android API 24).
- `Viper.wrap` with the launcher (dragged to eight spots, tucked to an edge tab, hidden) and the
  panel in a kept web view, in bridge mode, with a skeleton until it's ready.
- The markers (`markers.dart`) that fold away without `--dart-define=VIPER=true`.
- `tool/check_artifact.sh` for the production and staging builds.
- The phone's screenshot (native on iOS and Android, Flutter's own as the fallback, none on a
  secure window), masked before it's encoded, uploaded as the device picture the report names.
- The picking handle with Whole screen.
- Masking at every level through clips and transforms; the launcher above the app's bottom bar.
- The console and network a report carries, and the HTTP wrapper that leaves pinning alone.
- Picking a widget, a box or the dialog on top; screens and surfaces from the navigators.
- Shake to open, hide and show; identity refresh; viper:highlight; unsent pictures kept on the
  phone; the panel's file inputs on Android.
