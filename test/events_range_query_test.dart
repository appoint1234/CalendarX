import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:calendar/core/db/app_db.dart';
import 'package:drift/drift.dart';


void main() {
  test('watchEventsInRange returns overlapping events (cross-day included)', () async {
    final db = AppDb(NativeDatabase.memory());

    final start = DateTime(2026, 1, 21, 23, 30);
    final end = DateTime(2026, 1, 22, 0, 30);

    await db.createEvent(EventsCompanion.insert(
      title: '跨日事件',
      startAt: start,
      endAt: end,
      allDay: const Value(false),
    ));

    final rangeFrom = DateTime(2026, 1, 22, 0, 0);
    final rangeTo = DateTime(2026, 1, 22, 23, 59);

    final list = await db.watchEventsInRange(rangeFrom, rangeTo).first;
    expect(list.any((e) => e.title == '跨日事件'), true);

    await db.close();
  });
}
