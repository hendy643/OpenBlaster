// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/app_state.dart';
import 'src/client.dart';
import 'src/local_client.dart';
import 'src/single_instance.dart';
import 'src/tray.dart';

/// Command line:
///   --background  start hidden in the tray (what the login autostart uses)
///   --no-tray     no tray icon: closing the window quits (for development)
///   --verbose     log to the terminal what the window asks of the card and what comes back
///   --demo        no hardware: a made-up card, to look at the window
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final verbose = args.contains('--verbose');
  void log(String line) => debugPrint('openblaster: $line');

  final demo = args.contains('--demo');
  // A second copy asks the first to show itself, then quits. (A demo is for looking at, so it may run
  // beside the real one.)
  if (!demo &&
      !await claimSingleInstance(() async {
        await windowManager.show();
        await windowManager.focus();
      })) {
    exit(0);
  }

  final OpenBlasterClient client = demo
      ? LocalClient.demo()
      : LocalClient.real(log: verbose ? log : null);
  final state = AppState(client, log: verbose ? log : null);
  runApp(OpenBlasterApp(state: state, followSystem: true));
  if (!args.contains('--no-tray')) {
    await setUpTray(background: args.contains('--background'));
  }
  await state.start();
}
