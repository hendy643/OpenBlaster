// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'app_state.dart';
import 'ui/home_page.dart';

/// The window, in the Yaru theme. With [followSystem] the accent colour and light or dark come from the
/// GNOME settings; without it (the tests) the plain Yaru themes are used, so nothing reads the desktop.
class OpenBlasterApp extends StatelessWidget {
  const OpenBlasterApp({
    super.key,
    required this.state,
    this.followSystem = false,
  });

  final AppState state;
  final bool followSystem;

  Widget _app(ThemeData light, ThemeData dark) => MaterialApp(
    title: 'OpenBlaster',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: light,
    darkTheme: dark,
    home: HomePage(state: state),
  );

  @override
  Widget build(BuildContext context) {
    if (!followSystem) return _app(yaruLight, yaruDark);
    return YaruTheme(
      builder: (context, yaru, _) => _app(yaru.theme, yaru.darkTheme),
    );
  }
}
