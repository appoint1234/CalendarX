import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static int reminderNotificationId(int eventId) => 100000 + eventId;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;

    // timezone
    tzdata.initializeTimeZones();
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        print("[notify] tapped id=${resp.id} payload=${resp.payload} actionId=${resp.actionId}");
      },
    );

    print("[notify] init tzId=${info.identifier} tzLocal=${tz.local.name} now=${DateTime.now()} offset=${DateTime.now().timeZoneOffset}");

    _inited = true;
  }

  Future<void> requestAndroidPermissionIfNeeded() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    final notifGranted = await android.requestNotificationsPermission();
    final notifEnabled = await android.areNotificationsEnabled();
    final canExact = await android.canScheduleExactNotifications();

    print("[notify] requestNotificationsPermission=$notifGranted, "
        "areNotificationsEnabled=$notifEnabled, "
        "canScheduleExactNotifications=$canExact");

    if (canExact == false) {
      await android.requestExactAlarmsPermission();
    }
  }

  NotificationDetails _eventDetails() {
    const androidDetails = AndroidNotificationDetails(
      'event_reminder_v2',
      'Event Reminders',
      channelDescription: 'CalendarX event reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'CalendarX',
    );
    return const NotificationDetails(android: androidDetails);
  }

  Future<void> scheduleEventReminder({
    required int notificationId,
    required String title,
    required String body,
    required DateTime fireAtLocal,
    bool debugWatch = false,
    bool debugImmediate = false,
  }) async {
    await init();
    await requestAndroidPermissionIfNeeded();

    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final canExact = await android?.canScheduleExactNotifications() ?? true;

    final details = _eventDetails();
    final when = tz.TZDateTime.from(fireAtLocal, tz.local);

    try {
      await _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        when,
        details,
        androidScheduleMode: canExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: "scheduled:id=$notificationId fireAt=$fireAtLocal",
      );

      print("[notify] zonedSchedule OK id=$notificationId when=$fireAtLocal canExact=$canExact tzLocal=${tz.local.name}");

      if (debugImmediate) {
        await _plugin.show(
          notificationId + 900000,
          "[debug] immediate same channel",
          "If you see this, channel is visible. Scheduled at: $fireAtLocal",
          details,
        );
      }

      if (debugWatch) {
        _watchDelivery(notificationId, fireAtLocal);
      }
    } catch (e, st) {

      print("[notify] zonedSchedule FAILED id=$notificationId err=$e\n$st");
      rethrow;
    }
  }

  void _watchDelivery(int id, DateTime fireAtLocal) {
    final delay = fireAtLocal.difference(DateTime.now()) + const Duration(seconds: 2);
    final d = delay.isNegative ? Duration.zero : delay;

    Timer(d, () async {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final active = await android?.getActiveNotifications() ?? [];
      final pending = await _plugin.pendingNotificationRequests();

      final isActive = active.any((n) => n.id == id);
      final isPending = pending.any((p) => p.id == id);

      print("[notify] watch id=$id now=${DateTime.now()} fireAt=$fireAtLocal "
          "active=$isActive pending=$isPending activeIds=${active.map((e) => e.id).toList()}");
    });
  }

  Future<void> debugSelfTest10s() async {
    await init();
    await requestAndroidPermissionIfNeeded();

    final details = _eventDetails();

    final base = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    final nowId = 990000 + base;
    final schedId = 991000 + base;

    await _plugin.show(
      nowId,
      '通知自测',
      '如果你看到这条，说明“立即通知/通道/权限”OK',
      details,
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final canExact = await android?.canScheduleExactNotifications() ?? true;

    final fireAt = DateTime.now().add(const Duration(seconds: 10));
    final when = tz.TZDateTime.from(fireAt, tz.local);

    await _plugin.zonedSchedule(
      schedId,
      '通知自测(10秒)',
      '如果你看到这条，说明“定时调度”OK',
      when,
      details,
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: "selftest:id=$schedId fireAt=$fireAt",
    );

    // ignore: avoid_print
    print("[notify] selfTest nowId=$nowId schedId=$schedId fireAtLocal=$fireAt canExact=$canExact tzLocal=${tz.local.name}");
    _watchDelivery(schedId, fireAt);
  }

  Future<void> cancel(int notificationId) => _plugin.cancel(notificationId);
  Future<void> cancelAll() => _plugin.cancelAll();
}
