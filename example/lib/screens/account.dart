// The Account tab: a form with a password field, which Standard masks (D331).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// The tab.
class AccountTab extends StatefulWidget {
  /// The tab.
  const AccountTab({super.key});

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  final _name = TextEditingController(text: 'Kalani Akana');
  final _email = TextEditingController(text: 'kalani@example.com');
  final _password = TextEditingController(text: 'correct horse');
  bool _saved = false;
  bool _secure = false;

  static const _secureChannel = MethodChannel('example/secure');

  static final _log = Logger('Account');

  /// What a real Save would do, so a report has console lines and a network call in it (D333):
  /// a print, a warning through package:logging, and a call to the app's "API" (a path the local
  /// Viper doesn't have, so it answers 404 with a request id).
  Future<void> _save() async {
    // ignore: avoid_print
    print('Saving the profile for ${_name.text}');
    final client = HttpClient();
    try {
      final request = await client.putUrl(Uri.parse('http://localhost:4830/api/profile?user=7'));
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode >= 400) _log.warning('Profile save failed: the server answered ${response.statusCode}');
    } on IOException catch (error) {
      _log.warning('Profile save failed: $error');
    } finally {
      client.close();
    }
    if (mounted) setState(() => _saved = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const ValueKey('name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('email'),
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('password'),
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          key: const ValueKey('save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
        if (_saved) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Saved.')),
        if (Platform.isAndroid)
          SwitchListTile(
            key: const ValueKey('secure'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Secure window (FLAG_SECURE)'),
            subtitle: const Text('As an app lock sets it: Viper takes no picture.'),
            value: _secure,
            onChanged: (on) async {
              await _secureChannel.invokeMethod<void>('set', on);
              setState(() => _secure = on);
            },
          ),
      ],
    );
  }
}
