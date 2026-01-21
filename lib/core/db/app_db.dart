import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_db.g.dart';


class EventSearchRow {
  final Event event;
  final String? sourceName;
  const EventSearchRow({required this.event, this.sourceName});
}

class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get remindBeforeMinutes => integer().nullable()();
  IntColumn get notificationId => integer().nullable()();
  IntColumn get sourceId => integer().nullable()();     // 订阅源 id（本地手动创建的事件为 null）


  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get externalUid => text().nullable()();    // VEVENT 的 UID，用于同源去重

  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();

  BoolColumn get allDay => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  
  
}

class CalendarSources extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();        // 用户自定义名称
  TextColumn get url => text()();         // 订阅地址（.ics）
  TextColumn get etag => text().nullable()();
  TextColumn get lastModified => text().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
}

class CalendarSyncLogs extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get sourceId => integer()(); // 关联 CalendarSources.id

  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  IntColumn get durationMs => integer().nullable()();

  // success / not_modified / failed
  TextColumn get status => text()();

  IntColumn get httpStatus => integer().nullable()();
  IntColumn get itemCount => integer().nullable()();

  TextColumn get message => text().nullable()(); // 错误原因/补充信息
}


@DriftDatabase(tables: [Events, CalendarSources, CalendarSyncLogs])
class AppDb extends _$AppDb {
  AppDb([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion =>6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(
          events,
          events.remindBeforeMinutes as GeneratedColumn<Object>,
        );
        await m.addColumn(
          events,
          events.notificationId as GeneratedColumn<Object>,
        );
      }
      if (from < 3) {
        await m.createTable(calendarSources);
        await m.addColumn(events, events.sourceId as GeneratedColumn<Object>);
        await m.addColumn(events, events.externalUid as GeneratedColumn<Object>);
      }
      if (from < 4) {
        await _createIndexes();
      }
      if (from < 5) {
        await m.createTable(calendarSyncLogs);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sync_logs_source_started ON calendar_sync_logs(source_id, started_at);',
        );
      }
      if (from < 6) {
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS uq_events_source_uid ON events(source_id, external_uid);',
        );
      }
    },
  );

  Future<void> _createIndexes() async {
    // drift 默认把 startAt -> start_at 这种 snake_case 存到 sqlite
    await customStatement('CREATE INDEX IF NOT EXISTS idx_events_start_end ON events(start_at, end_at);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_events_source_uid ON events(source_id, external_uid);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_events_title ON events(title);');
  } 

  // CRUD
  Future<int> createEvent(EventsCompanion data) => into(events).insert(data);

  Future<void> updateEventById(int id, EventsCompanion data) =>
      (update(events)..where((t) => t.id.equals(id))).write(
        data.copyWith(updatedAt: Value(DateTime.now())),
      );

  Future<void> deleteEventById(int id) =>
      (delete(events)..where((t) => t.id.equals(id))).go();


  Future<int> startSyncLog(int sourceId) async {
    return into(calendarSyncLogs).insert(
      CalendarSyncLogsCompanion.insert(
        sourceId: sourceId,
        startedAt: DateTime.now(),
        status: 'running',
      ),
    );
  }

  Future<void> finishSyncLog({
    required int logId,
    required String status, // success / not_modified / failed
    int? httpStatus,
    int? itemCount,
    String? message,
  }) async {
    final finished = DateTime.now();
    final log = await (select(calendarSyncLogs)..where((t) => t.id.equals(logId))).getSingle();
    final dur = finished.difference(log.startedAt).inMilliseconds;

    await (update(calendarSyncLogs)..where((t) => t.id.equals(logId))).write(
      CalendarSyncLogsCompanion(
        finishedAt: Value(finished),
        durationMs: Value(dur),
        status: Value(status),
        httpStatus: Value(httpStatus),
        itemCount: Value(itemCount),
        message: Value(message),
      ),
    );

    // 同时更新源的 lastSyncAt
    await (update(calendarSources)..where((s) => s.id.equals(log.sourceId))).write(
        CalendarSourcesCompanion(lastSyncAt: Value(finished)),
      );
    }

  Stream<List<CalendarSyncLog>> watchSyncLogsBySource(int sourceId, {int limit = 20}) {
    final q = (select(calendarSyncLogs)
          ..where((t) => t.sourceId.equals(sourceId))
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
          ..limit(limit));
    return q.watch();
  }

  Stream<List<Event>> watchEventsInRange(DateTime from, DateTime to) {
    // 简单区间：与 [from,to] 有交集的事件都取出来
    final q = select(events)
      ..where((t) => t.endAt.isBiggerOrEqualValue(from) & t.startAt.isSmallerOrEqualValue(to))
      ..orderBy([(t) => OrderingTerm.asc(t.startAt)]);
    return q.watch();
  }

  Future<List<Event>> getAllEvents() => select(events).get();


  Future<Event?> getEvent(int id) =>
      (select(events)..where((t) => t.id.equals(id))).getSingleOrNull();


  

  Stream<List<CalendarSource>> watchSources() =>
    (select(calendarSources)..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();

  Future<int> createSource(CalendarSourcesCompanion data) =>
      into(calendarSources).insert(data);

  Future<void> deleteSourceById(int id) async {
    // 删除源的同时，删掉该源导入的事件（MVP）
    await (delete(events)..where((e) => e.sourceId.equals(id))).go();
    await (delete(calendarSyncLogs)..where((l) => l.sourceId.equals(id))).go();
    await (delete(calendarSources)..where((s) => s.id.equals(id))).go();
  }

  Future<void> upsertEventFromSource({
    required int sourceId,
    required String uid,
    required EventsCompanion data,
  }) async {
    final exists = await (select(events)
          ..where((e) => e.sourceId.equals(sourceId) & e.externalUid.equals(uid)))
        .getSingleOrNull();

    if (exists == null) {
      await into(events).insert(
        data.copyWith(
          sourceId: Value(sourceId),
          externalUid: Value(uid),
        ),
      );
    } else {
      await (update(events)..where((e) => e.id.equals(exists.id))).write(
        data.copyWith(
          sourceId: Value(sourceId),
          externalUid: Value(uid),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<List<EventSearchRow>> searchEvents({
    required String keyword,
    required DateTime from,
    required DateTime to,
    bool? onlySubscribed,
    bool? allDay,
    bool? hasReminder,
    int limit = 200,
  }) async {
    final kw = keyword.trim();

    final q = select(events).join([
      leftOuterJoin(calendarSources, calendarSources.id.equalsExp(events.sourceId)),
    ]);

    // 与 [from, to) 有交集：start < to && end >= from
    q.where(events.startAt.isSmallerThanValue(to) & events.endAt.isBiggerOrEqualValue(from));

    if (onlySubscribed == true) {
      q.where(events.sourceId.isNotNull());
    }
    if (allDay == true) {
      q.where(events.allDay.equals(true));
    }
    if (hasReminder == true) {
      q.where(events.remindBeforeMinutes.isNotNull());

    }

    if (kw.isNotEmpty) {
      final pattern = '%$kw%';
      q.where(
        events.title.like(pattern) |
        events.description.like(pattern) |
        calendarSources.name.like(pattern),
      );
    }

    q.orderBy([OrderingTerm.asc(events.startAt)]);
    q.limit(limit);

    final rows = await q.get();
    return rows.map((row) {
      final e = row.readTable(events);
      final s = row.readTableOrNull(calendarSources);
      return EventSearchRow(event: e, sourceName: s?.name);
    }).toList();
  }

  //伪造数据，进行性能测试
  Future<int> seedRandomEvents({
    required int count,
    required DateTime fromDay,
    int spanDays = 30,
  }) async {
    final now = DateTime.now();
    final list = <EventsCompanion>[];

    for (int i = 0; i < count; i++) {
      final dayOffset = i % spanDays;
      final day = DateTime(fromDay.year, fromDay.month, fromDay.day).add(Duration(days: dayOffset));
      final startHour = (i * 37) % 24;
      final start = DateTime(day.year, day.month, day.day, startHour, (i * 13) % 60);
      final end = start.add(Duration(minutes: 30 + (i % 90)));

      list.add(EventsCompanion.insert(
        title: 'Perf-$i',
        description: const Value('seed'),
        startAt: start,
        endAt: end,
        allDay: const Value(false),
        remindBeforeMinutes: Value(i % 3 == 0 ? 10 : null),
      ));
    }

    await batch((b) {
      b.insertAll(events, list);
    });

    return count;
  }

}

LazyDatabase _open() {
  return LazyDatabase(() async {
    return driftDatabase(name: 'calendarx.sqlite');
  });
}



