import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/auth/app_role.dart';
import '../core/auth/auth_provider.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_provider.dart';
import '../core/widgets/connectivity_banner.dart';

class MotusApp extends ConsumerStatefulWidget {
  const MotusApp({super.key});

  @override
  ConsumerState<MotusApp> createState() => _MotusAppState();
}

class _MotusAppState extends ConsumerState<MotusApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_restoreRememberedSession);
  }

  Future<void> _restoreRememberedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('auth_remember_me') ?? true;
    final controller = ref.read(authControllerProvider.notifier);
    if (rememberMe) {
      await controller.restoreSession();
    } else {
      await controller.signOut();
    }
  }

  String _homeForRole(AppRole? role) {
    return switch (role) {
      AppRole.secretary => '/secretary-dashboard',
      AppRole.technician => '/technician-dashboard',
      AppRole.admin || AppRole.manager => '/admin-dashboard',
      _ => '/login',
    };
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final auth = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'MOTUS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent ||
                event.logicalKey != LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            }

            // ESC önce açık dialog / popup / route'u kapatır. MaterialApp.builder
            // context'i Navigator'ın üstünde kaldığı için Navigator.maybeOf(context)
            // güvenilir değildir; doğrudan GoRouter'ın root navigator key'ini kullanıyoruz.
            final navigator = rootNavigatorKey.currentState;
            if (navigator != null && navigator.canPop()) {
              navigator.maybePop();
              return KeyEventResult.handled;
            }

            final currentPath =
                router.routerDelegate.currentConfiguration.uri.path;
            final fallback = backFallbackRoute(currentPath, auth.role);
            if (fallback != currentPath) {
              router.go(fallback);
            }
            return KeyEventResult.handled;
          },
          child: ConnectivityBanner(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
