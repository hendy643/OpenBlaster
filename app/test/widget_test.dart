// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/app.dart';
import 'package:openblaster/src/app_state.dart';

import 'support/fake_client.dart';

import 'package:openblaster/src/models.dart';

Future<(FakeClient, AppState)> open(
  WidgetTester tester, {
  FakeClient? client,
}) async {
  final fake = client ?? FakeClient();
  final state = AppState(fake);
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(OpenBlasterApp(state: state));
  await tester.runAsync(state.start);
  await tester.pumpAndSettle();
  return (fake, state);
}

void main() {
  testWidgets('no card says so', (tester) async {
    await open(tester, client: FakeClient()..deviceName = null);
    expect(find.text('No Sound Blaster card found'), findsOneWidget);
  });

  testWidgets('the card is named in the title and the pages are listed', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Sound BlasterX AE-5 Plus (demo)'), findsOneWidget);
    final rail = find.byKey(const Key('pages'));
    for (final page in ['Output', 'Speakers', 'Effects', 'Equalizer']) {
      expect(
        find.descendant(of: rail, matching: find.text(page)),
        findsOneWidget,
        reason: page,
      );
    }
  });

  testWidgets('a switch sends its new state', (tester) async {
    final (client, state) = await open(tester);
    await tester.tap(find.byKey(const Key('control-volume.mute')));
    await tester.pumpAndSettle();
    expect(client.sets, [('volume.mute', 1)]);
    expect(state.controls.firstWhere((c) => c.id == 'volume.mute').value, 1);
  });

  testWidgets(
    'a choice of few short items is a segmented button and sends the index',
    (tester) async {
      final (client, _) = await open(tester);
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      await tester.tap(find.text('Headphone'));
      await tester.pumpAndSettle();
      expect(client.sets, [('output.select', 1)]);
    },
  );

  testWidgets('a long list of choices is a dropdown', (tester) async {
    final (client, _) = await open(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('pages')),
        matching: find.text('Speakers'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5.1').last);
    await tester.pumpAndSettle();
    expect(client.sets, [('speakers.layout', 4)]);
  });

  testWidgets('a slider shows its value and sends where it was released', (
    tester,
  ) async {
    final (client, state) = await open(tester);
    expect(find.text('50'), findsOneWidget);
    final slider = find.descendant(
      of: find.byKey(const Key('control-volume.master')),
      matching: find.byType(Slider),
    );
    await tester.drag(slider, const Offset(150, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(client.sets, isNotEmpty);
    final last = client.sets.last;
    expect(last.$1, 'volume.master');
    expect(last.$2, greaterThan(50));
    expect(last.$2, lessThanOrEqualTo(99));
    expect(
      state.controls.firstWhere((c) => c.id == 'volume.master').value,
      last.$2,
    );
  });

  testWidgets('a change made elsewhere moves the slider', (tester) async {
    final (client, _) = await open(tester);
    client.externalChange('volume.master', 80);
    await tester.pumpAndSettle();
    expect(find.text('80'), findsOneWidget);
  });

  testWidgets('a refused change puts the control back and tells the user', (
    tester,
  ) async {
    final (client, state) = await open(tester);
    client.failNext = const ControlError(
      'Failed',
      'the hardware refused the change',
    );
    await tester.tap(find.byKey(const Key('control-volume.mute')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('the hardware refused the change'),
      findsOneWidget,
    );
    expect(state.controls.firstWhere((c) => c.id == 'volume.mute').value, 0);
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('control-volume.mute')),
    );
    expect(tile.value, isFalse);
  });

  testWidgets('a read-only or unreadable control cannot be operated', (
    tester,
  ) async {
    await open(
      tester,
      client: FakeClient(
        controls: const [
          Control(
            id: 'a.ro',
            group: 'G',
            label: 'Locked',
            kind: ControlKind.toggle,
            writable: false,
            value: 1,
          ),
          Control(
            id: 'a.na',
            group: 'G',
            label: 'Unreadable',
            kind: ControlKind.range,
            max: 10,
            available: false,
          ),
        ],
      ),
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('control-a.ro')))
          .onChanged,
      isNull,
    );
    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const Key('control-a.na')),
        matching: find.byType(Slider),
      ),
    );
    expect(slider.onChanged, isNull);
  });

  testWidgets('switching pages shows that page\'s controls only', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Crystalizer'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('pages')),
        matching: find.text('Effects'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Crystalizer'), findsOneWidget);
    expect(find.text('Volume'), findsNothing);
  });

  testWidgets('a colour opens a picker and sends the chosen colour', (
    tester,
  ) async {
    final (client, state) = await open(
      tester,
      client: FakeClient(
        controls: const [
          Control(
            id: 'lighting.color1',
            group: 'Lighting',
            label: 'Colour 1',
            kind: ControlKind.color,
            max: 0xffffff,
            value: 0x1e88e5,
          ),
        ],
      ),
    );
    expect(state.groups, ['Lighting']);
    await tester.tap(find.byKey(const Key('control-lighting.color1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preset-ff0000')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('color-ok')));
    await tester.pumpAndSettle();
    expect(client.sets, [('lighting.color1', 0xff0000)]);
    expect(state.controls.single.value, 0xff0000);
  });

  testWidgets('typing a hex colour is accepted, cancelling sends nothing', (
    tester,
  ) async {
    final (client, _) = await open(
      tester,
      client: FakeClient(
        controls: const [
          Control(
            id: 'lighting.color1',
            group: 'Lighting',
            label: 'Colour 1',
            kind: ControlKind.color,
            max: 0xffffff,
            value: 0,
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('control-lighting.color1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('hex')), '00ff7f');
    await tester.tap(find.byKey(const Key('color-ok')));
    await tester.pumpAndSettle();
    expect(client.sets, [('lighting.color1', 0x00ff7f)]);

    await tester.tap(find.byKey(const Key('control-lighting.color1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.sets, hasLength(1));
  });
}
