import 'dart:convert';
import 'package:enough_icalendar/enough_icalendar.dart';
import '../../core/db/app_db.dart';
import 'package:drift/drift.dart';

class IcsService {
  /// 把数据库事件列表导出为一个 VCALENDAR 文本
  String exportToIcs({
    required List<Event> events,
    String productId = 'CalendarX//ICS Export',
    String calendarName = 'CalendarX',
  }) {
    final cal = VCalendar()
      ..productId = productId
      ..version = '2.0'
      ..calendarScale = 'GREGORIAN'
      ..calendarName = calendarName;

    for (final e in events) {
      final ve = VEvent(parent: cal)
        ..uid = 'event-${e.id}@calendarx.local'
        ..timeStamp = DateTime.now().toUtc()
        ..summary = e.title
        ..description = e.description
        ..start = e.startAt
        ..end = e.endAt;
      cal.children.add(ve);
    }
    return cal.toString();
  }

  /// 解析 ICS 文本，提取 VEVENT
  List<EventsCompanion> importFromIcs(String icsText) {
    final root = VComponent.parse(icsText);
    final cal = root is VCalendar ? root : null;
    if (cal == null) return const [];

    final vevents = cal.children.whereType<VEvent>();

    final result = <EventsCompanion>[];
    for (final ve in vevents) {
      final start = ve.start;
      final end = ve.end;

      // 没有时间就跳过
      if (start == null) continue;

      final title = (ve.summary?.trim().isNotEmpty ?? false) ? ve.summary!.trim() : 'Untitled';
      final desc = ve.description?.trim();

      // 兜底：如果没有 DTEND，用 1 小时
      final fixedEnd = (end != null && end.isAfter(start)) ? end : start.add(const Duration(hours: 1));

      result.add(
        EventsCompanion.insert(
          title: title,
          description: Value(desc),
          startAt: start,
          endAt: fixedEnd,
          allDay: const Value(false), // MVP：不严格判断 all-day，后面再升级
        ),
      );
    }

    return result;
  }

  /// 小工具：把 ics 文件里可能的 BOM/奇怪编码处理一下
  String normalize(String raw) {
    final bytes = utf8.encode(raw);
    return utf8.decode(bytes, allowMalformed: true).replaceAll('\r\n', '\n');
  }
}

class IcsImportItem {
  final String uid;
  final EventsCompanion data;
  IcsImportItem({required this.uid, required this.data});
}

extension IcsImportWithUid on IcsService {
  /// 解析 ICS 并返回 (uid + 事件数据)，用于订阅源“同源去重/更新”
  List<IcsImportItem> importWithUid(String icsText) {
    final root = VComponent.parse(icsText);
    final cal = root is VCalendar ? root : null;
    if (cal == null) return const [];

    final vevents = cal.children.whereType<VEvent>();
    final result = <IcsImportItem>[];

    for (final ve in vevents) {
      final start = ve.start;
      if (start == null) continue;

      final end = ve.end;
      final fixedEnd =
          (end != null && end.isAfter(start)) ? end : start.add(const Duration(hours: 1));

      final uid = (ve.uid?.trim().isNotEmpty ?? false)
          ? ve.uid!.trim()
          : 'no-uid-${start.millisecondsSinceEpoch}-${(ve.summary ?? '').hashCode}';

      final title =
          (ve.summary?.trim().isNotEmpty ?? false) ? ve.summary!.trim() : 'Untitled';
      final desc = ve.description?.trim();

      final data = EventsCompanion.insert(
        title: title,
        startAt: start,
        endAt: fixedEnd,
        description: Value(desc),
        allDay: const Value(false),
      );

      result.add(IcsImportItem(uid: uid, data: data));
    }

    return result;
  }
}

