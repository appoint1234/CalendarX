import 'dart:developer' as developer;
import 'dart:developer' as dev;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:ui' as ui;

class AlarmReminder {
  AlarmReminder._();

  static const int _kBaseId = 1000000;
  static const String _channelId = 'calendar_event_reminders';
  static const String _channelName = 'Event Reminders';
  static const String _channelDesc = 'Calendar event reminders';

  static int _alarmIdForEvent(int eventId) => _kBaseId + eventId;

  static Future<void> init() async {
    final ok = await AndroidAlarmManager.initialize();
    developer.log('[alarm] initialize ok=$ok');
  }

  static Future<void> debugSelfTest() async {
    final now = DateTime.now();
    final fireAt = now.add(const Duration(seconds: 5));
    final id = _kBaseId + 999999; 
    developer.log('[alarm] selfTest schedule id=$id fireAt=$fireAt');
    final ok = await AndroidAlarmManager.oneShotAt(
      fireAt,
      id,
      alarmEntryPoint,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      params: <String, dynamic>{
        'title': 'calendar • selfTest',
        'body': 'If you see this, Alarm callback works. Scheduled at: $fireAt',
      },
    );
    print('[alarm] selfTest scheduled ok=$ok');
  }

  static Future<bool> cancelEventReminder(int eventId) async {
    final id = _alarmIdForEvent(eventId);
    final ok = await AndroidAlarmManager.cancel(id);
    print('[alarm] cancel ok=$ok eventId=$eventId id=$id');
    return ok;
  }

  static Future<bool> scheduleEventReminder({
    required int eventId,
    required String title,
    required String body,
    required DateTime fireAtLocal,
  }) async {
    final id = _alarmIdForEvent(eventId);

    await AndroidAlarmManager.cancel(id);

    developer.log('[alarm] schedule start eventId=$eventId id=$id fireAtLocal=$fireAtLocal');

    final ok = await AndroidAlarmManager.oneShotAt(
      fireAtLocal,
      id,
      alarmEntryPoint,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      params: <String, dynamic>{
        'eventId': eventId,
        'title': title,
        'body': body,
        'fireAtLocalIso': fireAtLocal.toIso8601String(),
      },
    );

    print('[alarm] scheduled ok=$ok eventId=$eventId id=$id fireAtLocal=$fireAtLocal');
    return ok;
  }

}

@pragma('vm:entry-point')
Future<void> alarmEntryPoint(int id, Map<String, dynamic> params) async {
  // 让后台 isolate 可以使用插件（关键）
  ui.DartPluginRegistrant.ensureInitialized();

  final plugin = FlutterLocalNotificationsPlugin();

  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );

  // 后台 isolate 里一般没 initialize，保险起见初始化一下
  await plugin.initialize(initSettings);

  // 确保渠道存在（Android 8+）
  const channelId = 'calendar_event_reminders';
  const channelName = 'Event Reminders';
  const channelDesc = 'Calendar event reminders';

  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.max,
    ),
  );

  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    ),
  );

  final title = (params['title'] ?? '日程提醒').toString();
  final body = (params['body'] ?? '').toString();

  await plugin.show(id, title, body, details);

  print('[alarm] SHOW OK id=$id');
}

