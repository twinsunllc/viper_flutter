# viper_flutter

Viper for Flutter apps (Stage I, `docs/build/tracks/flutter.md`). On an app's staging build a
tester taps the launcher, says what's wrong, and the report lands in Viper with what was on screen,
the logs and the device, for Claude to draft and a person to publish. The panel is the one Viper
already ships, in a web view (D328); this package plays the loader's part.

Built in the Viper repo (`flutter/viper_flutter`) and published to `twinsunllc/viper_flutter`,
which apps use as a git dependency (D339).

**Status:** built (track U, slices 1 to 6). Next: the first tag, published to
`twinsunllc/viper_flutter`, and the Set&Co pilot (`docs/build/tracks/flutter.md`, "The pilot").

## The screenshot (D330, D331, D338)

When a person picks the whole screen, Viper hides its own launcher and sheet for a frame and takes
the phone's picture natively, so platform views come out as they look (a Liquid Glass tab bar, a
native map): on iOS the key window through `drawViewHierarchyInRect`, on Android a `PixelCopy` of
the Flutter surface, or of the window when a hybrid composition view is on screen. When the native
call fails, Flutter draws it (`toImage`), with platform views blocked and the capture saying so. A
window with Android's `FLAG_SECURE` (an app lock) gets no picture at all, on purpose, and the report
says why. What the project's privacy level hides is filled before the PNG is encoded, so it never leaves the
phone (D331):

| Level | Hidden |
|---|---|
| Standard | obscured text fields, anything under `ViperPrivate`, every embedded web view |
| Strict | every text field, every image (`Image`, an avatar's photo, a decoration image, an SVG), every platform view, `ViperPrivate` |
| Maximum | all text and images except under `ViperUnmask`, every field and platform view, `ViperPrivate` |

Only what is painted is masked: a hidden tab, a route under another, an `Offstage` child are left
alone, each box goes through every transform, and it's cut to its ancestors' clips (a scrolled
list's edges, a `ClipRRect`). `ViperUnmask` shows text and images at Maximum, never a field. The picture
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
3. **The `VIPER_COMMIT` define (D356).** CI writes the head commit beside `VIPER` in the staging
   flavor's dart-define file (`"VIPER_COMMIT": "<git rev-parse HEAD>"`, or
   `--dart-define=VIPER_COMMIT=$(git rev-parse HEAD)`). Viper tells from it whether a tester has a
   fix (D353, D357): "The fix is in build 1041. Update in TestFlight." Without it, Viper names the
   build by the app's own build string only and holds nothing.

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

## Picking and screens (D332)

Report something shrinks the sheet to a handle across the bottom (D169). Tap what you mean: Viper
hit tests the app, finds the widget that owns what was tapped, and names it the way people say it
("Save button", "Password field", "Kalani Akana, lead card"); the panel's breadcrumb steps up to
what holds it. Or pick the whole screen, the dialog on top, or draw a box. The anchor carries the
widget's type, its `ValueKey`, its semantics label, its text and its box, so give the widgets
testers report on a `ValueKey`.

The screen is the page on top of the innermost navigator on screen (a tab's own navigator inside
the app's), read from the navigator itself. Its key is, in order:

1. the nearest `ViperScreen`'s name,
2. the route's `settings.name` (other than the "/" every first route gets),
3. the type of the widget the route built (`JobListScreen` is "Job list").

A dialog, a bottom sheet, a menu, an open drawer and the tab a navigation bar shows are the
screen's surfaces. Renaming a screen's class makes a new screen in Viper, which staff can merge.

## Console and network (D333)

A report carries the last 200 console lines and 100 network calls, as on the web:

- **Console:** what the app prints (`print`, `debugPrint`) inside `Viper.runZoned`; errors from
  `FlutterError.onError` and `PlatformDispatcher.onError`, chained to what the app set, so
  Crashlytics keeps working; whatever the app's own zone handler passes to `Viper.recordError`;
  and `package:logging` records, heard without changing the app's level.
- **Network:** every `dart:io` `HttpClient` call (including `package:http` and Dio on mobile):
  method, origin and path, status, duration and a request id header (`x-request-id` and the
  like). Never a body. It doesn't see web sockets or native SDKs' own traffic.
- At Strict and Maximum, console text is masked and queries are stripped (D80).

Viper chains to the error handlers set when `Viper.start` runs: set Crashlytics (or any
`FlutterError.onError` and `PlatformDispatcher.onError`) before `onBoot`, or a handler set later
replaces Viper's and the console loses those errors. It wraps the `HttpOverrides` current when
`Viper.start` runs too, which is why `onBoot` comes before the app builds its clients. An override the app installs later (certificate pinning) must chain to
the one before it:

```dart
class PinnedOverrides extends HttpOverrides {
  PinnedOverrides({this.previous});
  final HttpOverrides? previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = previous?.createHttpClient(context) ?? super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => pinned(cert, host);
    return client;
  }
}

HttpOverrides.global = PinnedOverrides(previous: HttpOverrides.current);
```

Pinning still applies through Viper's wrapper: it forwards every property to the client it wraps.

## The launcher (D335)

Bottom right by default, or where the project's settings start it (D295). A bottom spot sits
above the app's bottom navigation bar or tab bar and the bottom safe area (D351); a project's own
raise wins. Drag it to any of the eight spots; long press to tuck it to an edge tab (and back), or
to **Hide Viper**. Shaking the phone opens Viper, hidden or not; a project can turn shake off in its
settings, and then hiding isn't offered, nor where the phone can't feel a shake (the iOS simulator
has no accelerometer; on the Android emulator, shake it from Extended controls > Virtual sensors). Where it sits
and whether it's hidden are remembered per install, and turning the phone or resizing an iPad split
view puts it back on its spot. It reads as one button to VoiceOver and TalkBack, with the counts in
its label and tuck and hide as actions.

The panel's web view is made once, as soon as Viper says the app is trusted, and kept for the life
of the app, so it's ready when the launcher is tapped. The device log says how long it took:

```
Viper: panel ready 1449 ms after the web view was made
Viper: launcher tapped; the panel was already ready (kept web view, 0 ms)
```

## Identity and signing in (D21, D86, D334)

Give Viper the signed-in person when the app knows them, from a signature the app's backend makes
with the staging environment's identity secret (the same `v1` string the web uses; the setup's
install step has the Node and Supabase Edge Function snippets):

```dart
Viper.start(key: ..., host: ..., identity: () async => api.viperIdentity());   // at start
Viper.identify(signed, refresh: () async => api.viperIdentity());              // after sign-in
Viper.identify(null);                                                          // after sign-out
```

A minute before a signature expires, `refresh` (or the start's `identity`) is asked for a fresh
one. Without an identity, a tester tells Viper their name the first time they report, or signs in:
**Sign in** opens Viper's sign-in page in the system's in-app browser (SFSafariViewController, a
Custom Tab), which always asks "Finish signing in" and then says to go back to the app; the panel
picks the session up on its own, and on iOS the browser view closes.

## Keeping what's in progress

The panel's draft and view are kept on the phone, so a web view the OS killed comes back where it
was (D108). A report that can't reach Viper waits and goes once it can (D165), with the picture it
was taken with, kept on the phone until it's sent, even across a restart. Coming back to the app
reconnects the panel's live updates.

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

4. **Report something.** Tap the launcher, then Report something, then tap what's wrong (the
   Account tab's Save button, say), or Whole screen on the handle at the bottom. Say what's wrong
   and Send; tell Viper your name, or Sign in as `wilfred@twinsunsolutions.com` with the seeded
   password. Save on the Account tab first and the report carries a print, a logged warning and a
   network call.

5. **See it in the staff portal**: `http://localhost:4830/staff/projects/harbor/items`, signed in
   as Wilfred. The item shows the phone's picture (masked as the project's level says), the
   Environment card for the device, the console and network lines, and the widget named.

6. **Or against staging**, with no local Viper: Harbor's staging environment on staging trusts the
   example's ID.

   ```sh
   flutter run -d <simulator or emulator> -t lib/main_staging.dart --dart-define=VIPER=true \
     --dart-define=VIPER_HOST=https://viper-volatile.twinsun.dev --dart-define=VIPER_KEY=hbr_7Qk2
   ```

   The item lands in staging's staff portal, `https://viper-volatile.twinsun.dev/staff/projects/harbor/items`.

Also worth a try: hide the launcher from its long press and shake it back (a phone or the Android
emulator); turn the phone; open a
dialog and pick This dialog; on Android, turn on Account's "Secure window" and see the report say
there's no picture.

The integration tests do this on a device against a local Viper: `integration_test/panel_test.dart`
opens the panel, and `integration_test/report_test.dart` reports three whole screens (a form with
its password masked, a native view, a web view) and a tapped button on a tab's own navigator, and
on Android checks a `FLAG_SECURE` window gets no picture:
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
