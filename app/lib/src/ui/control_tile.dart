// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';

/// One control as a row: a switch, a slider or a choice, by its kind.
class ControlTile extends StatelessWidget {
  const ControlTile({
    super.key,
    required this.control,
    required this.onChanged,
  });

  final Control control;
  final void Function(int value) onChanged;

  @override
  Widget build(BuildContext context) {
    switch (control.kind) {
      case ControlKind.toggle:
        return SwitchListTile(
          key: Key('control-${control.id}'),
          title: Text(control.label),
          value: (control.value ?? 0) != 0,
          onChanged: control.enabled ? (v) => onChanged(v ? 1 : 0) : null,
        );
      case ControlKind.range:
        return _RangeTile(control: control, onChanged: onChanged);
      case ControlKind.choice:
        return _ChoiceTile(control: control, onChanged: onChanged);
      case ControlKind.color:
        return _ColorTile(control: control, onChanged: onChanged);
    }
  }
}

class _RangeTile extends StatefulWidget {
  const _RangeTile({required this.control, required this.onChanged});

  final Control control;
  final void Function(int value) onChanged;

  @override
  State<_RangeTile> createState() => _RangeTileState();
}

class _RangeTileState extends State<_RangeTile> {
  // While the thumb is down its own position wins over what the card reports back.
  double? _dragging;
  Timer? _throttle;
  int? _pending;

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  void _send(int v) {
    // Live feedback, but not more often than the card and the bus can take.
    if (_throttle?.isActive ?? false) {
      _pending = v;
      return;
    }
    widget.onChanged(v);
    _throttle = Timer(const Duration(milliseconds: 60), () {
      final p = _pending;
      _pending = null;
      if (p != null) widget.onChanged(p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.control;
    final span = c.max - c.min;
    final current = _dragging ?? (c.value ?? c.min).toDouble();
    return ListTile(
      key: Key('control-${c.id}'),
      title: Row(
        children: [
          Expanded(child: Text(c.label)),
          Text(
            '${current.round()}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
      subtitle: Slider(
        min: c.min.toDouble(),
        max: c.max.toDouble(),
        divisions: span > 0 && span <= 1000 ? (span / c.step).round() : null,
        value: current.clamp(c.min.toDouble(), c.max.toDouble()),
        onChanged: c.enabled
            ? (v) {
                setState(() => _dragging = v);
                _send(v.round());
              }
            : null,
        onChangeEnd: c.enabled
            ? (v) {
                _throttle?.cancel();
                _pending = null;
                setState(() => _dragging = null);
                widget.onChanged(v.round());
              }
            : null,
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.control, required this.onChanged});

  final Control control;
  final void Function(int value) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = control;
    final short =
        c.choices.length <= 3 && c.choices.every((s) => s.length <= 12);
    return ListTile(
      key: Key('control-${c.id}'),
      title: Text(c.label),
      trailing: short
          ? SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (var i = 0; i < c.choices.length; i++)
                  ButtonSegment(value: i, label: Text(c.choices[i])),
              ],
              selected: {c.value ?? 0},
              onSelectionChanged: c.enabled ? (s) => onChanged(s.first) : null,
            )
          : DropdownButton<int>(
              value: c.value,
              onChanged: c.enabled ? (v) => onChanged(v!) : null,
              items: [
                for (var i = 0; i < c.choices.length; i++)
                  DropdownMenuItem(value: i, child: Text(c.choices[i])),
              ],
            ),
    );
  }
}

const _presets = [
  0xff0000,
  0xff7f00,
  0xffff00,
  0x00ff00,
  0x00ffff,
  0x1e88e5,
  0x0000ff,
  0x8000ff,
  0xff00ff,
  0xffffff,
];

/// A colour: its swatch opens a picker with sliders, a hex field and presets.
class _ColorTile extends StatelessWidget {
  const _ColorTile({required this.control, required this.onChanged});

  final Control control;
  final void Function(int value) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = control;
    final value = c.value ?? 0;
    return ListTile(
      key: Key('control-${c.id}'),
      title: Text(c.label),
      trailing: Container(
        key: Key('swatch-${c.id}'),
        width: 48,
        height: 28,
        decoration: BoxDecoration(
          color: Color(0xFF000000 | value),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      enabled: c.enabled,
      onTap: c.enabled
          ? () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) => _ColorDialog(title: c.label, initial: value),
              );
              if (picked != null) onChanged(picked);
            }
          : null,
    );
  }
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.title, required this.initial});
  final String title;
  final int initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late int _value = widget.initial;
  late final _hex = TextEditingController(text: _hexOf(widget.initial));

  static String _hexOf(int v) => v.toRadixString(16).padLeft(6, '0');

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(int v) => setState(() {
    _value = v & 0xffffff;
    _hex.text = _hexOf(_value);
  });

  Widget _channel(String name, int shift, Color color) => Row(
    children: [
      SizedBox(width: 16, child: Text(name)),
      Expanded(
        child: Slider(
          key: Key('channel-$name'),
          activeColor: color,
          max: 255,
          value: ((_value >> shift) & 0xff).toDouble(),
          onChanged: (v) =>
              _set((_value & ~(0xff << shift)) | (v.round() << shift)),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Color(0xFF000000 | _value),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            _channel('R', 16, Colors.red),
            _channel('G', 8, Colors.green),
            _channel('B', 0, Colors.blue),
            TextField(
              key: const Key('hex'),
              controller: _hex,
              maxLength: 6,
              decoration: const InputDecoration(
                prefixText: '#',
                labelText: 'Hex',
              ),
              onChanged: (t) {
                final v = t.length == 6 ? int.tryParse(t, radix: 16) : null;
                if (v != null) setState(() => _value = v);
              },
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in _presets)
                  InkWell(
                    key: Key('preset-${_hexOf(p)}'),
                    onTap: () => _set(p),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | p),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('color-ok'),
          onPressed: () => Navigator.pop(context, _value),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
