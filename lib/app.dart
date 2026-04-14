import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'config/app_theme.dart';
import 'config/app_routes.dart';
import 'providers/auth_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/welfare_standards_provider.dart';

import 'providers/application_provider.dart';

class CareWayApp extends StatelessWidget {
  const CareWayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => WelfareStandardsProvider()..load()),
        ChangeNotifierProxyProvider<AuthProvider, ApplicationProvider>(
          create: (_) => ApplicationProvider(),
          update: (_, auth, appProvider) {
            final provider = appProvider ?? ApplicationProvider();
            provider.setCurrentUser(auth.currentUser?.id);
            return provider;
          },
        ),
      ],
      child: Builder(
        builder: (context) {
          final router = createRouter(context);
          return MaterialApp.router(
            title: 'CareWay',
            theme: AppTheme.light,
            routerConfig: router,
            locale: const Locale('ko', 'KR'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('ko', 'KR'),
              Locale('en', 'US'),
            ],
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
