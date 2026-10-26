// The Account tab: a form with a password field, which Standard masks (D331).
import 'package:flutter/material.dart';

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
          onPressed: () => setState(() => _saved = true),
          child: const Text('Save'),
        ),
        if (_saved) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Saved.')),
      ],
    );
  }
}
