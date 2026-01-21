import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:calendar/core/db/app_db.dart';

void main() {
  test('upsertEventFromSource updates existing row by (sourceId, uid)', () async {
    final db = AppDb(NativeDatabase.memory());

    final sourceId = await db.createSource(CalendarSourcesCompanion.insert(
      name: 'Test',
      url: 'https://example.com/a.ics',
    ));

    await db.upsertEventFromSource(
      sourceId: sourceId,
      uid: 'uid-1',
      data: EventsCompanion.insert(
        title: '第一次',
        startAt: DateTime(2026, 1, 21, 10, 0),
        endAt: DateTime(2026, 1, 21, 11, 0),
        allDay: const Value(false),
        description: const Value('v1'),
      ),
    );

    await db.upsertEventFromSource(
      sourceId: sourceId,
      uid: 'uid-1',
      data: EventsCompanion.insert(
        title: '第二次',
        startAt: DateTime(2026, 1, 21, 10, 0),
        endAt: DateTime(2026, 1, 21, 11, 0),
        allDay: const Value(false),
        description: const Value('v2'),
      ),
    );

    final all = await db.getAllEvents();
    expect(all.length, 1);
    expect(all.first.title, '第二次');
    expect(all.first.description, 'v2');

    await db.close();
  });
}
