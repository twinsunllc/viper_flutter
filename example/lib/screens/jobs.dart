// The Jobs tab: a long list in its own navigator, so nested navigators and scrolled lists are
// there to report from (D332, D331).
import 'package:flutter/material.dart';
import 'package:viper_flutter/markers.dart';

/// The tab, with its own navigator and its own observer.
class JobsTab extends StatefulWidget {
  /// The tab.
  const JobsTab({super.key});

  @override
  State<JobsTab> createState() => _JobsTabState();
}

class _JobsTabState extends State<JobsTab> {
  final NavigatorObserver _observer = Viper.observer();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      observers: [_observer],
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            settings.name == '/job' ? JobDetailsScreen(number: settings.arguments as int? ?? 1) : const JobListScreen(),
      ),
    );
  }
}

/// Forty jobs.
class JobListScreen extends StatelessWidget {
  /// The list.
  const JobListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const ValueKey('job-list'),
      itemCount: 40,
      itemBuilder: (context, i) => ListTile(
        key: ValueKey('job-$i'),
        leading: CircleAvatar(child: Text('${i + 1}')),
        title: Text('Job ${i + 1}: ${_places[i % _places.length]}'),
        subtitle: Text('Call time ${6 + i % 5}:00 a.m.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/job', arguments: i + 1),
      ),
    );
  }

  static const _places = ['Kakaako warehouse', 'Diamond Head lot', 'Waimanalo beach', 'Chinatown loft', 'Manoa valley'];
}

/// One job, pushed on the tab's own navigator.
class JobDetailsScreen extends StatelessWidget {
  /// Job [number].
  const JobDetailsScreen({required this.number, super.key});

  /// Which job.
  final int number;

  @override
  Widget build(BuildContext context) {
    return ViperScreen(
      name: 'Job details',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Job $number', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Rate: \$650 a day. Wardrobe provided.'),
          const SizedBox(height: 16),
          FilledButton(key: const ValueKey('accept-job'), onPressed: () {}, child: const Text('Accept')),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to jobs')),
        ],
      ),
    );
  }
}
