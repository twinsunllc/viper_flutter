// The Crew tab: an image, a dialog and a bottom sheet (D331, D18's surfaces).
import 'package:flutter/material.dart';
import 'package:viper_flutter/markers.dart';

/// The tab.
class CrewTab extends StatelessWidget {
  /// The tab.
  const CrewTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset('assets/crew.png', key: const ValueKey('crew-image'), height: 160, fit: BoxFit.cover),
        ),
        const SizedBox(height: 12),
        const Text('Lead: Kalani Akana', style: TextStyle(fontWeight: FontWeight.w600)),
        const ViperPrivate(child: Text('Home phone: (808) 555-0142')),
        const SizedBox(height: 16),
        OutlinedButton(
          key: const ValueKey('open-dialog'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Leave the crew?'),
              content: const Text('You will stop getting calls for this crew.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Stay')),
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Leave')),
              ],
            ),
          ),
          child: const Text('Leave the crew'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('open-sheet'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    title: Text('Share the call sheet', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.message),
                    title: const Text('Text it'),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.email),
                    title: const Text('Email it'),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
          child: const Text('Share the call sheet'),
        ),
      ],
    );
  }
}
