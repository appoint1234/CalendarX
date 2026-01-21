import 'package:flutter/material.dart';
import 'router.dart';
import 'theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';


class CalendarXApp extends StatelessWidget {
  const CalendarXApp({super.key});

  @override
  Widget build(BuildContext context) {
    
    return MaterialApp.router(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      title: 'CalendarLV',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
  }
}
