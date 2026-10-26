# viper_flutter

Viper for Flutter apps (Stage I, `docs/build/tracks/flutter.md`). On an app's staging build a
tester taps the launcher, says what's wrong, and the report lands in Viper with what was on screen,
the logs and the device, for Claude to draft and a person to publish. The panel is the one Viper
already ships, in a web view (D328); this package plays the loader's part.

Built in the Viper repo (`flutter/viper_flutter`) and published to `twinsunllc/viper_flutter`,
which apps use as a git dependency (D339).

**Status:** slice 2 of 6. The launcher, the panel in its sheet, the bridge, and the phone's
masked screenshot uploaded with the report work. While picking, the sheet is a handle offering the
whole screen; tapping an element, the full masking tests, console and network, shake and identity
refresh come in the next slices.

## The screenshot (D330, D331, D338)

When a person picks the whole screen, Viper hides its own launcher and sheet for a frame and takes
the phone's picture natively, so platform views come out as they look (a Liquid Glass tab bar, a
native map): on iOS the key window through `drawViewHierarchyInRect`, on Android a `PixelCopy` of
the Flutter surface, or of the window when a hybrid composition view is on screen. When the native
call fails, Flutter draws it (`toImage`), with platform views blocked and the capture saying so. A
window with Android's `FLAG_SECURE` (an app lock) gets no picture at all, on purpose, and the report
says why. What the project's privacy level hides (passwords and `ViperPrivate` at Standard, every
embedded web view) is filled before the PNG is encoded, so it never leaves the phone. The picture
goes to Viper first (`POST /widget/device_pictures`); the report names it, and only a thumbnail
crosses into the panel.

## Install

```yaml
dependencies:
  viper_flutter:
    git:
      url: git@github.com:twinsunllc/viper_flutter.git
      ref: flutter-v0.1.0
```

Flutter 3.44 or later. iOS builds through Swift Package Manager or CocoaPods. Viper runs on iOS
16.4 and up and Android 7 (API 24) and up; below that `Viper.start` does nothing and the app runs as
normal (D338).

## Staging only (D336)

Viper is in a build only when that build asks for it, twice over:

1. **Only the staging entry point imports the implementation.** `main_staging.dart` imports
   `package:viper_flutter/viper_flutter.dart` and calls `Viper.start`. Everything else imports
   `package:viper_flutter/markers.dart`, which never imports the implementation or `dart:io`. A
   production build from `main.dart` never contains Viper's code.
2. **The `VIPER` define.** Every entry point checks `const bool.fromEnvironment('VIPER')`. Put
   `"VIPER": true` in the staging flavor's dart-define file only (or pass
   `--dart-define=VIPER=true`). Without it the markers fold to their child and the compiler drops
   the rest.

```dart
// lib/main_staging.dart: the only file that imports the implementation.
import 'package:viper_flutter/viper_flutter.dart';
import 'package:my_app/main.dart' as app;

void main() => Viper.runZoned(() => app.main(onBoot: () => Viper.start(
  key: 'vk_...',                                   // the staging environment's widget key
  host: Uri.parse('https://viper-volatile.twinsun.dev'),
  identity: () async => api.viperIdentity(),       // optional: a signed identity (D21, D86)
  context: () => {'plan': user.plan},              // optional: added to every capture (D27)
)));
```

`main()` calls `onBoot` after its own setup (Crashlytics, Firebase) and before it builds its HTTP
clients. `Viper.start` never waits on the network, so the first frame and an offline launch don't
wait on Viper.

In shared code, from `markers.dart`:

```dart
MaterialApp(
  navigatorObservers: [_viperObserver],            // one Viper.observer() per navigator, kept in a field
  builder: (context, child) => Viper.wrap(child: child!),
);

ViperScreen(name: 'Cast hub', child: ...);         // names a screen (D332)
ViperPrivate(child: ...);                          // masked at every level (D331)
ViperUnmask(child: ...);                           // shown at Maximum (D331)
Viper.identify(signedIdentity);                    // after sign-in, or null after sign-out
Viper.recordError(error, stack);                   // from the app's own zone handler (D333)
```

Don't build staging with `--obfuscate`: screen and widget names come from type names (D332).

### Checking a build

`tool/check_artifact.sh` reads a built artifact's Dart snapshot for the implementation's marker
(`viper-flutter-implementation`), the Viper host and the key:

```sh
tool/check_artifact.sh build/app/outputs/flutter-apk/app-release.apk refuse --key vk_...   # production: no Viper
tool/check_artifact.sh build/ios/iphoneos/Runner.app/Frameworks/App.framework expect --key vk_...  # staging: Viper is in it
```

It takes a `libapp.so`, an `App.framework`, or an `.apk`, `.aab` or `.ipa`, needs a release or
profile build (a debug build has no snapshot), and never prints the host or the key. CI runs both
directions on the example's Android release builds.

## The launcher (D335)

Bottom right by default, or where the project's settings start it (D295). Drag it to any of the
eight spots; long press to tuck it to an edge tab (and back). Where it sits is remembered per
install. Hiding it ("Hide Viper", brought back by a shake) arrives with shake in slice 6. It reads
as one button to VoiceOver and TalkBack, with the counts in its label and tuck as an action.

The panel's web view is made once, as soon as Viper says the app is trusted, and kept for the life
of the app, so it's ready when the launcher is tapped. The device log says how long it took:

```
Viper: panel ready 1449 ms after the web view was made
Viper: launcher tapped; the panel was already ready (kept web view, 0 ms)
```

## How to try it

You need a local Viper (Rails on port 4830 here, with its own database) and the example app on a
simulator or an emulator. The example's ID, `dev.twinsun.viper.example`, is trusted by the seeded
local environment of Harbor, key `hbr_loc_9w` (D342), which the example uses by default.

1. **Run Viper.** From the repo root, with Postgres (4832) and Redis (4879) up
   (`docker compose up -d`):

   ```sh
   pnpm install && pnpm --filter @viper/protocol build && pnpm --filter @viper/widget build
   cd web && pnpm install && pnpm build && pnpm build:css
   export DATABASE_URL=postgres://postgres:postgres@localhost:4832/viper_try REDIS_URL=redis://localhost:4879/7
   export APP_PORT=4830 APP_HOST=localhost:4830   # so sign-in and links stay on this port
   bin/rails db:create db:schema:load db:seed      # prints the people, the password and the example's key
   bin/rails server -p 4830 -b 0.0.0.0
   ```

   A Flutter capture needs no renderer; Sidekiq marks it rendered. Without Sidekiq running, its
   picture still shows, and `bin/rails runner 'Capture.where(render_status: :pending, platform:
   :flutter).find_each { |c| Captures::RenderJob.perform_now(c.id) }'` marks it.

2. **Run the example on the iOS simulator.** It reaches the Mac at `localhost:4830`:

   ```sh
   cd flutter/viper_flutter/example
   flutter run -d <simulator> -t lib/main_staging.dart --dart-define=VIPER=true
   ```

3. **Or on an Android emulator.** Forward the port so the emulator's localhost is the Mac's:

   ```sh
   adb reverse tcp:4830 tcp:4830
   flutter run -d emulator-5554 -t lib/main_staging.dart --dart-define=VIPER=true
   ```

   Not `10.0.2.2`: over plain HTTP only localhost is a secure context, and outside one the web
   view sends no `Sec-Fetch-Site`, so Viper refuses the panel's own reads (403). A deployed Viper
   is HTTPS and has no such problem.

   Another Viper or key: `--dart-define=VIPER_HOST=... --dart-define=VIPER_KEY=...`.

4. **Report something.** Tap the launcher, then Report something, then Whole screen on the handle
   at the bottom. Say what's wrong and Send; tell Viper your name, or sign in as
   `wilfred@twinsunsolutions.com` with the seeded password.

5. **See it in the staff portal**: `http://localhost:4830/staff/projects/harbor/items`, signed in
   as Wilfred. The item shows the phone's picture and an Environment card for the device.

The integration tests do this on a device: `integration_test/panel_test.dart` opens the panel, and
`integration_test/report_test.dart` reports three whole screens (a form with its password masked,
a native view, a web view) and, on Android, checks a `FLAG_SECURE` window gets no picture:
`flutter test integration_test/report_test.dart -d <device> --dart-define=VIPER=true`.

## Developing

```sh
flutter pub get && (cd example && flutter pub get)
dart format .
flutter analyze
tool/test.sh            # the tests without the define, the markers with it, and the example's
```

The tests write the JSON the package sends to `test/fixtures/<Type>/<case>.json` (D340, D343);
commit them. `pnpm --filter @viper/protocol fixtures` at the repo root validates them against the
protocol's schemas, and CI fails when a test changed a fixture that wasn't committed.
