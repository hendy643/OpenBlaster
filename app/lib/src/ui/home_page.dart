// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'control_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _group;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_showMessage);
  }

  @override
  void dispose() {
    widget.state.removeListener(_showMessage);
    super.dispose();
  }

  void _showMessage() {
    final text = widget.state.message;
    if (text == null || !mounted) return;
    widget.state.clearMessage();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.device?.name ?? 'OpenBlaster'),
            actions: [
              IconButton(
                key: const Key('refresh'),
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: s.refresh,
              ),
            ],
          ),
          body: switch (s.status) {
            AppStatus.connecting => const Center(
              child: CircularProgressIndicator(),
            ),
            AppStatus.noDevice => _Notice(
              icon: Icons.speaker_group_outlined,
              title: 'No Sound Blaster card found',
              detail: 'OpenBlaster did not find a supported card.',
              onRetry: s.refresh,
            ),
            AppStatus.ready => _pages(s),
          },
        );
      },
    );
  }

  Widget _pages(AppState s) {
    final groups = s.groups;
    if (groups.isEmpty) {
      return const Center(child: Text('This card offers no controls.'));
    }
    final group = groups.contains(_group) ? _group! : groups.first;
    final controls = s.controlsIn(group);
    return Row(
      children: [
        NavigationRail(
          key: const Key('pages'),
          selectedIndex: groups.indexOf(group),
          labelType: NavigationRailLabelType.all,
          onDestinationSelected: (i) => setState(() => _group = groups[i]),
          destinations: [
            for (final g in groups)
              NavigationRailDestination(
                icon: Icon(_iconFor(g)),
                label: Text(g),
              ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            key: PageStorageKey(group),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final c in controls)
                ControlTile(
                  key: ValueKey(c.id),
                  control: c,
                  onChanged: (v) => s.set(c, v),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _iconFor(String group) => switch (group) {
    'Output' => Icons.volume_up_outlined,
    'Speakers' => Icons.speaker_outlined,
    'Input' => Icons.mic_none_outlined,
    'Effects' => Icons.auto_awesome_outlined,
    'Equalizer' => Icons.equalizer_outlined,
    'Microphone' => Icons.settings_voice_outlined,
    'Lighting' => Icons.lightbulb_outline,
    'Virtual surround' => Icons.surround_sound_outlined,
    _ => Icons.tune_outlined,
  };
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SelectableText(detail),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('retry'),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
