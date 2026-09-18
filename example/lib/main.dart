import 'package:flutter/material.dart';
import 'package:zero_tap_easy/zero_tap_easy.dart';

/// A bench for exercising the three restore-key operations by hand.
///
/// Restore keys are WebAuthn credentials, so create and get both need options
/// JSON from a relying-party server. Paste it into the field below — or point
/// the field at whatever your server returns — and watch the log.
///
/// What you can check without a server:
///   * [ZeroTapEasy.isSupported] reports correctly for the device.
///   * `Get` returns "no restore key" rather than throwing on a fresh install.
///   * `Clear` succeeds when there is nothing to clear.
void main() => runApp(const ZeroTapDemoApp());

/// The example application.
class ZeroTapDemoApp extends StatelessWidget {
  /// Creates the example application.
  const ZeroTapDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'zero_tap_easy',
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
        ),
        home: const _HomePage(),
      );
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  final TextEditingController _requestJson = TextEditingController();
  final List<String> _log = <String>[];

  bool _supported = false;
  bool _busy = false;
  bool _cloudBackup = true;

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  @override
  void dispose() {
    _requestJson.dispose();
    super.dispose();
  }

  void _write(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  Future<void> _checkSupport() async {
    final bool supported = await ZeroTapEasy.isSupported();
    if (!mounted) return;
    setState(() => _supported = supported);
    _write(
      supported
          ? 'Supported: Android 9+ with a current Play services.'
          : 'Not supported here. Restore keys need Android 9+ with Play '
              'services 24220000+.',
    );
  }

  /// Wraps an operation with busy state and uniform error reporting.
  Future<void> _run(String label, Future<void> Function() body) async {
    setState(() => _busy = true);
    _write('--- $label ---');
    try {
      await body();
    } on ZeroTapException catch (e) {
      _write('${e.code}: ${e.message}');
    } catch (e) {
      _write('Unexpected: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run('Create', () async {
        final RestoreKeyCreation result = await ZeroTapEasy.createRestoreKey(
          _requestJson.text,
          isCloudBackupEnabled: _cloudBackup,
        );
        _write(
          result.usedCloudBackup
              ? 'Created with cloud backup.'
              : 'Created LOCAL ONLY — this key will not survive a cloud '
                  'restore, only a device-to-device transfer.',
        );
        _write('POST this to your server: ${result.responseJson}');
      });

  Future<void> _get() => _run('Get', () async {
        final String? assertion =
            await ZeroTapEasy.getRestoreKey(_requestJson.text);
        if (assertion == null) {
          _write('No restore key on this device. Show your sign-in screen.');
        } else {
          _write('Assertion for your server to verify: $assertion');
        }
      });

  Future<void> _clear() => _run('Clear', () async {
        await ZeroTapEasy.clearRestoreKey();
        _write('Restore key cleared.');
      });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = _supported && !_busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('zero_tap_easy'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _busy
              ? const LinearProgressIndicator(minHeight: 4)
              : const SizedBox(height: 4),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              color: _supported
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Icon(_supported ? Icons.check_circle : Icons.block),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _supported
                            ? 'Restore keys supported on this device'
                            : 'Restore keys not supported on this device',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _requestJson,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'requestJson from your relying-party server',
                helperText: 'Creation options for Create, request options for Get',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _cloudBackup,
              onChanged: enabled
                  ? (bool value) => setState(() => _cloudBackup = value)
                  : null,
              title: const Text('isCloudBackupEnabled'),
              subtitle: const Text(
                'Off means a local-only key. Falls back automatically when the '
                'device has no backup or screen lock.',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed: enabled ? _create : null,
                  child: const Text('Create'),
                ),
                FilledButton.tonal(
                  onPressed: enabled ? _get : null,
                  child: const Text('Get'),
                ),
                OutlinedButton(
                  onPressed: enabled ? _clear : null,
                  child: const Text('Clear'),
                ),
                TextButton(
                  onPressed: _busy ? null : _checkSupport,
                  child: const Text('Re-check support'),
                ),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: _log.isEmpty
                  ? const Center(child: Text('No output yet.'))
                  : ListView.builder(
                      reverse: false,
                      itemCount: _log.length,
                      itemBuilder: (BuildContext context, int i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SelectableText(
                          _log[i],
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
