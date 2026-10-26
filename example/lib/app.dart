// The example app: every kind of screen Viper has to report from (flutter.md, track U slice 1).
// A list, a form with a password field, a dialog, a bottom sheet, a drawer, tabs on an
// IndexedStack (one with its own navigator), an image, a web view and a native platform view.
// Shared code like this imports only markers.dart (D336).
import 'package:flutter/material.dart';
import 'package:viper_flutter/markers.dart';
import 'package:viper_flutter_example/screens/account.dart';
import 'package:viper_flutter_example/screens/crew.dart';
import 'package:viper_flutter_example/screens/jobs.dart';
import 'package:viper_flutter_example/screens/native_view.dart';
import 'package:viper_flutter_example/screens/web_page.dart';

/// Set&Co's shape (flutter.md, the Dart API): main takes an onBoot hook, called after the app's
/// own setup and before it builds its HTTP clients.
void main({void Function()? onBoot}) {
  WidgetsFlutterBinding.ensureInitialized();
  onBoot?.call();
  runApp(const ExampleApp());
}

/// The app.
class ExampleApp extends StatefulWidget {
  /// The app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  // One observer per navigator, held in state rather than built in build (D332).
  final NavigatorObserver _observer = Viper.observer();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Viper example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3B6EF5), useMaterial3: true),
      navigatorObservers: [_observer],
      builder: (context, child) => Viper.wrap(child: child!),
      home: const HomeShell(),
      routes: {
        '/web': (_) => const WebPageScreen(),
        '/native': (_) => const NativeViewScreen(),
      },
    );
  }
}

/// The shell: a drawer, and three tabs on an IndexedStack, so a hidden tab stays built.
class HomeShell extends StatefulWidget {
  /// The shell.
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['Jobs', 'Crew', 'Account'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_tab])),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text('Viper example', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              ListTile(
                key: const ValueKey('drawer-web'),
                leading: const Icon(Icons.public),
                title: const Text('Web page'),
                onTap: () => Navigator.of(context)
                  ..pop()
                  ..pushNamed('/web'),
              ),
              ListTile(
                key: const ValueKey('drawer-native'),
                leading: const Icon(Icons.phone_iphone),
                title: const Text('Native view'),
                onTap: () => Navigator.of(context)
                  ..pop()
                  ..pushNamed('/native'),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(index: _tab, children: const [JobsTab(), CrewTab(), AccountTab()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'Jobs'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Crew'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}
