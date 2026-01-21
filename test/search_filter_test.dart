import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:calendar/core/db/app_db.dart';

void main() {
  test('searchEvents supports keyword + filters', () async {
    final db = AppDb(NativeDatabase.memory());

    final sourceId = await db.createSource(CalendarSourcesCompanion.insert(
      name: '国内日历',
      url: 'https://example.com/cn.ics',
    ));

    // 本地事件（非订阅）
    await db.createEvent(EventsCompanion.insert(
      title: '买菜',
      startAt: DateTime(2026, 1, 21, 9, 0),
      endAt: DateTime(2026, 1, 21, 10, 0),
      allDay: const Value(false),
      remindBeforeMinutes: const Value(10),
    ));

    // 订阅事件
    await db.upsertEventFromSource(
      sourceId: sourceId,
      uid: 'uid-cn-1',
      data: EventsCompanion.insert(
        title: '会议',
        description: const Value('和客户开会'),
        startAt: DateTime(2026, 1, 21, 14, 0),
        endAt: DateTime(2026, 1, 21, 15, 0),
        allDay: const Value(false),
      ),
    );

    final res1 = await db.searchEvents(
      keyword: '会议',
      from: DateTime(2026, 1, 21),
      to: DateTime(2026, 1, 22),
      onlySubscribed: true,
    );
    expect(res1.length, 1);
    expect(res1.first.event.title, '会议');

    final res2 = await db.searchEvents(
      keyword: '',
      from: DateTime(2026, 1, 21),
      to: DateTime(2026, 1, 22),
      hasReminder: true,
    );
    expect(res2.any((r) => r.event.title == '买菜'), true);

    await db.close();
  });
}
