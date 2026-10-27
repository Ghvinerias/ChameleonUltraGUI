import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../apk_source.dart';
import '../install_wizard.dart';
import '../watch_installer.dart';
import 'error_banner.dart';
import 'strings.dart';

/// Phone-sized wizard: checklist, pair, connect, APK source, install, launch, aftercare.
class InstallWizardPage extends StatefulWidget {
  const InstallWizardPage({super.key, this.installer, this.fetcher});

  /// Injectable for tests; defaults to the ADB-over-Wi-Fi implementation.
  final WatchInstaller? installer;
  final ApkFetcher? fetcher;

  @override
  State<InstallWizardPage> createState() => _InstallWizardPageState();
}

class _InstallWizardPageState extends State<InstallWizardPage> {
  late final InstallWizardController c = InstallWizardController(
    installer: widget.installer ?? AdbWifiInstaller(),
    fetcher: widget.fetcher ?? DefaultApkFetcher(),
  );

  final host = TextEditingController();
  final pairPort = TextEditingController();
  final code = TextEditingController();
  final connectPort = TextEditingController();
  late final url = TextEditingController(text: c.apkUrl);

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _resolvePackageName();
  }

  /// The watch app has the same application id as this app (dev builds carry a
  /// `.dev` suffix), so use our own id instead of the store id.
  Future<void> _resolvePackageName() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted && info.packageName.isNotEmpty) {
        c.packageName = info.packageName;
      }
    } catch (_) {
      // Keep the default (store id), e.g. in widget tests without the plugin.
    }
  }

  void _onChange() {
    if (!mounted) return;
    if (c.step == WizardStep.pair || c.step == WizardStep.checklist) {
      // The pairing code is single-use; never keep it around after an attempt.
      if (c.error != null) code.clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    c.finish();
    c.dispose();
    for (final t in [host, pairPort, code, connectPort, url]) {
      t.dispose();
    }
    super.dispose();
  }

  int? _port(TextEditingController t) {
    final p = int.tryParse(t.text.trim());
    return (p != null && p > 0 && p < 65536) ? p : null;
  }

  bool get _hostOk => RegExp(r'^[A-Za-z0-9.\-:]+$').hasMatch(host.text.trim());

  void _invalid() => ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text(InstallerStrings.invalidInput)));

  Future<void> _confirmForget() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(InstallerStrings.forgetButton),
        content: const Text(InstallerStrings.forgetConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(InstallerStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(InstallerStrings.ok),
          ),
        ],
      ),
    );
    if (yes == true) {
      await c.forgetWatch();
      if (mounted && c.forgotten) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(InstallerStrings.forgotten)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(InstallerStrings.pageTitle),
        actions: [
          IconButton(
            tooltip: InstallerStrings.forgetButton,
            icon: const Icon(Icons.link_off),
            onPressed: c.busy ? null : _confirmForget,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LinearProgressIndicator(
              value: (c.step.index + 1) / WizardStep.values.length,
            ),
            const SizedBox(height: 16),
            ..._stepBody(context),
            if (c.error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(
                error: c.error!,
                action:
                    c.step == WizardStep.install &&
                        c.error!.type == WatchInstallErrorType.signatureMismatch
                    ? _uninstallAction()
                    : null,
              ),
            ],
            if (c.busy) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _uninstallAction() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(InstallerStrings.uninstallWarning),
      TextButton(
        onPressed: c.busy ? null : c.uninstallAndReinstall,
        child: const Text(InstallerStrings.uninstallRetry),
      ),
    ],
  );

  Widget _title(String s) =>
      Text(s, style: Theme.of(context).textTheme.headlineSmall);

  Widget _backButton() => TextButton(
    onPressed: c.busy ? null : c.back,
    child: const Text(InstallerStrings.back),
  );

  Widget _field(
    TextEditingController t,
    String label, {
    TextInputType type = TextInputType.text,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: t,
      keyboardType: type,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  List<Widget> _stepBody(BuildContext context) {
    switch (c.step) {
      case WizardStep.checklist:
        return [
          _title(InstallerStrings.checklistTitle),
          const SizedBox(height: 8),
          const Text(InstallerStrings.checklistIntro),
          const SizedBox(height: 8),
          for (final s in const [
            InstallerStrings.checklistDevOptions,
            InstallerStrings.checklistAdb,
            InstallerStrings.checklistWifi,
            InstallerStrings.checklistPairHint,
          ])
            ListTile(
              dense: true,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(s),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: c.confirmChecklist,
            child: const Text(InstallerStrings.checklistConfirm),
          ),
        ];
      case WizardStep.pair:
        return [
          _title(InstallerStrings.pairTitle),
          const SizedBox(height: 8),
          const Text(InstallerStrings.pairIntro),
          _field(host, InstallerStrings.hostLabel, type: TextInputType.url),
          _field(
            pairPort,
            InstallerStrings.pairPortLabel,
            type: TextInputType.number,
          ),
          _field(
            code,
            InstallerStrings.pairCodeLabel,
            type: TextInputType.number,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: c.busy
                ? null
                : () {
                    final port = _port(pairPort);
                    if (!_hostOk || port == null || code.text.trim().isEmpty) {
                      return _invalid();
                    }
                    final value = code.text.trim();
                    code.clear();
                    c.pair(host.text.trim(), port, value);
                  },
            child: const Text(InstallerStrings.pairButton),
          ),
          Row(
            children: [
              _backButton(),
              TextButton(
                onPressed: c.busy ? null : c.skipPairing,
                child: const Text(InstallerStrings.alreadyPaired),
              ),
            ],
          ),
        ];
      case WizardStep.connect:
        return [
          _title(InstallerStrings.connectTitle),
          const SizedBox(height: 8),
          const Text(InstallerStrings.connectIntro),
          _field(host, InstallerStrings.hostLabel, type: TextInputType.url),
          _field(
            connectPort,
            InstallerStrings.connectPortLabel,
            type: TextInputType.number,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: c.busy
                ? null
                : () {
                    final port = _port(connectPort);
                    if (!_hostOk || port == null) return _invalid();
                    c.connect(host.text.trim(), port);
                  },
            child: const Text(InstallerStrings.connectButton),
          ),
          _backButton(),
        ];
      case WizardStep.apkSource:
        return [
          _title(InstallerStrings.apkTitle),
          const SizedBox(height: 8),
          Text(InstallerStrings.installedVersion(c.installedVersion)),
          _field(url, InstallerStrings.urlLabel, type: TextInputType.url),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.download),
            onPressed: c.busy
                ? null
                : () => c.useDownloadedApk(url.text.trim()),
            label: const Text(InstallerStrings.downloadButton),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open),
            onPressed: c.busy ? null : c.useLocalApk,
            label: const Text(InstallerStrings.pickButton),
          ),
          _backButton(),
        ];
      case WizardStep.install:
        final name = (c.apkPath ?? '').split('/').last;
        return [
          _title(InstallerStrings.installTitle),
          const SizedBox(height: 8),
          Text(InstallerStrings.installReady(name)),
          if (c.busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: c.progress),
            const SizedBox(height: 4),
            const Text(InstallerStrings.installing),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: c.busy ? null : c.install,
            child: const Text(InstallerStrings.installButton),
          ),
          _backButton(),
        ];
      case WizardStep.launch:
        return [
          _title(InstallerStrings.launchTitle),
          const SizedBox(height: 8),
          const Text(InstallerStrings.launchIntro),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: c.busy ? null : c.launch,
            child: const Text(InstallerStrings.launchButton),
          ),
          TextButton(
            onPressed: c.busy ? null : c.skipLaunch,
            child: const Text(InstallerStrings.skipButton),
          ),
        ];
      case WizardStep.aftercare:
        return [
          _title(InstallerStrings.aftercareTitle),
          const SizedBox(height: 8),
          const Text(InstallerStrings.aftercareText),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text(InstallerStrings.closeButton),
          ),
          TextButton(
            onPressed: c.busy ? null : _confirmForget,
            child: const Text(InstallerStrings.forgetButton),
          ),
        ];
    }
  }
}
