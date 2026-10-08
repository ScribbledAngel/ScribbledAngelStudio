import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

class ScribbledAngelStudioApp extends StatelessWidget {
  const ScribbledAngelStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..load(),
      child: MaterialApp(
        title: 'Scribbled Angel Studio',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const _AppRoot(),
      ),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (appState.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const HomeScreen();
  }
}
