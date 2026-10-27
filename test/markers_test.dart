// The markers shared code calls (D336): pass-throughs in a build without the define, slots once
// Viper.start fills them. `flutter test` runs the off half; `tool/test.sh` runs this file again
// with `--dart-define=VIPER=true` for the on half.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/markers.dart';
import 'package:viper_flutter/src/slots.dart';

class RecordingHandler implements ViperSlotHandler {
  final List<String> calls = [];

  @override
  Widget wrap(Widget child) {
    calls.add('wrap');
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        const Text('viper', textDirection: TextDirection.ltr),
      ],
    );
  }

  @override
  void recordError(Object error, StackTrace? stack) => calls.add('error $error');

  @override
  void identify(SignedIdentity? identity, {IdentityRefresh? refresh}) => calls.add('identify ${identity?['v']}');

  @override
  void context(Map<String, Object?> values) => calls.add('context $values');

  @override
  void routesChanged(ViperNavigatorObserver observer) => calls.add('routes');

  @override
  void show() => calls.add('show');

  @override
  void open() => calls.add('open');
}

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => CounterState();
}

class CounterState extends State<Counter> {
  int count = 0;

  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('$count', textDirection: TextDirection.ltr);
}

void main() {
  tearDown(() {
    ViperSlots.handler.value = null;
    ViperSlots.pendingContext.clear();
    ViperSlots.identityPending = false;
    ViperSlots.pendingIdentity = null;
  });

  group('without the VIPER define', skip: viperDefined ? 'runs without --dart-define=VIPER=true' : false, () {
    test('wrap is the child itself, even with a handler', () {
      ViperSlots.handler.value = RecordingHandler();
      const child = SizedBox();
      expect(identical(Viper.wrap(child: child), child), isTrue);
    });

    test('observer is a plain NavigatorObserver', () {
      expect(Viper.observer().runtimeType, NavigatorObserver);
    });

    test('identify, context, recordError, show and open do nothing', () {
      final handler = RecordingHandler();
      ViperSlots.handler.value = handler;
      Viper.identify({'v': 1});
      Viper.context({'plan': 'pro'});
      Viper.recordError(StateError('x'), null);
      Viper.show();
      Viper.open();
      expect(handler.calls, isEmpty);
      expect(ViperSlots.pendingContext, isEmpty);
    });

    testWidgets('the marker widgets are their child', (tester) async {
      await tester.pumpWidget(
        const ViperScreen(
          name: 'Cast hub',
          child: ViperPrivate(
            child: ViperUnmask(child: Text('x', textDirection: TextDirection.ltr)),
          ),
        ),
      );
      expect(find.text('x'), findsOneWidget);
    });
  });

  group('with the VIPER define', skip: viperDefined ? false : 'run by tool/test.sh with --dart-define=VIPER=true', () {
    testWidgets('wrap is a pass-through until start, then the handler, and the app keeps its state', (tester) async {
      await tester.pumpWidget(Viper.wrap(child: const Counter()));
      expect(find.text('viper'), findsNothing);
      for (var i = 0; i < 7; i++) {
        tester.state<CounterState>(find.byType(Counter)).bump();
      }
      await tester.pump();
      final handler = RecordingHandler();
      ViperSlots.handler.value = handler;
      await tester.pump();
      expect(find.text('viper'), findsOneWidget);
      expect(find.text('7'), findsOneWidget, reason: 'the app was moved under Viper, not rebuilt');
    });

    test('identify and context before start wait for it', () {
      Viper.identify({'v': 1});
      Viper.context({'plan': 'pro'});
      expect(ViperSlots.identityPending, isTrue);
      expect(ViperSlots.pendingIdentity, {'v': 1});
      expect(ViperSlots.pendingContext, {'plan': 'pro'});
    });

    test('show and open before start do nothing, and are never kept for later (D371)', () {
      Viper.show();
      Viper.open();
      final handler = RecordingHandler();
      ViperSlots.handler.value = handler;
      expect(handler.calls, isEmpty);
    });

    test('after start, every call reaches the handler', () {
      final handler = RecordingHandler();
      ViperSlots.handler.value = handler;
      Viper.identify({'v': 1});
      Viper.context({'plan': 'pro'});
      Viper.recordError('boom', StackTrace.empty);
      Viper.show();
      Viper.open();
      expect(handler.calls, ['identify 1', 'context {plan: pro}', 'error boom', 'show', 'open']);
    });

    testWidgets('an observer tells the handler when its navigator changes', (tester) async {
      final handler = RecordingHandler();
      ViperSlots.handler.value = handler;
      final observer = Viper.observer() as ViperNavigatorObserver;
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          navigatorObservers: [observer],
          onGenerateRoute: (settings) =>
              PageRouteBuilder<void>(settings: settings, pageBuilder: (_, _, _) => const SizedBox()),
        ),
      );
      expect(handler.calls, contains('routes'));
      expect(observer.routes.single.settings.name, '/');
      expect(ViperSlots.observers, contains(observer));
    });
  });
}
