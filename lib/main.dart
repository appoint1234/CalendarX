
import 'dart:developer' as dev;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:calendar/core/notify/alarm_reminder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/notify/notification_service.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final alarmOk = await AndroidAlarmManager.initialize();
  dev.log('[alarm] AndroidAlarmManager.initialize ok=$alarmOk', name: 'alarm');
  await NotificationService.instance.init();
  await NotificationService.instance.requestAndroidPermissionIfNeeded();
  await AlarmReminder.init();

  runApp(const ProviderScope(child: CalendarXApp()));
}
