// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// The tray icon and hide-on-close. Closing the window leaves OpenBlaster running in the tray (as it
/// does after the login autostart with --background); "Quit" in the tray menu ends it.
///
/// Returns false, and changes nothing, when there is no tray to put the icon in: then closing the
/// window quits, as it would for any program, and a --background start shows the window instead of
/// leaving it out of reach.
Future<bool> setUpTray({required bool background}) async {
  await windowManager.ensureInitialized();
  try {
    await trayManager.setIcon('assets/tray.png');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show OpenBlaster'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  } catch (e) {
    debugPrint('no tray icon: $e');
    if (background) await windowManager.show();
    return false;
  }
  try {
    await trayManager.setToolTip(
      'OpenBlaster',
    ); // not every platform has tooltips (Linux does not)
  } catch (_) {}
  await windowManager.setPreventClose(true);
  if (background) await windowManager.hide();
  final listener = _Listener();
  trayManager.addListener(listener);
  windowManager.addListener(listener);
  return true;
}

Future<void> _show() async {
  await windowManager.show();
  await windowManager.focus();
}

class _Listener with TrayListener, WindowListener {
  @override
  void onTrayIconMouseDown() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      await _show();
    }
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _show();
      case 'quit':
        exit(0); // settings are saved as they change
    }
  }

  @override
  void onWindowClose() => windowManager.hide();
}
