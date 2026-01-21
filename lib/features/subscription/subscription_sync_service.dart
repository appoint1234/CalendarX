import 'package:dio/dio.dart';
import '../../core/db/app_db.dart';
import '../ics/ics_service.dart';
import 'package:drift/drift.dart';



class SubscriptionSyncService {
  SubscriptionSyncService({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
          // 可选：跟随重定向
          followRedirects: true,
          // 可选：只要有数据就不算错
          validateStatus: (code) => code != null && code >= 200 && code < 400,
          
        )){
          print('SubscriptionSyncService created, connectTimeout=${_dio.options.connectTimeout}');
        }
  final Dio _dio;
  final _ics = IcsService();

  Future<int> addSourceAndSync(AppDb db, {required String name, required String url}) async {
    final id = await db.createSource(
      CalendarSourcesCompanion.insert(name: name, url: url),
    );
    await syncSource(db, sourceId: id);
    return id;
  }

  Future<void> syncSource(AppDb db, {required int sourceId}) async {
    print('connectTimeout=${_dio.options.connectTimeout}');
    final source = await (db.select(db.calendarSources)..where((t) => t.id.equals(sourceId)))
        .getSingle();
    final logId = await db.startSyncLog(sourceId);
    
    try {
      final resp = await _dio.get<String>(
        source.url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            if (source.etag != null) 'If-None-Match': source.etag!,
            if (source.lastModified != null) 'If-Modified-Since': source.lastModified!,
          },
        ),
      );

      // 304：没变化
      if (resp.statusCode == 304) {
        await (db.update(db.calendarSources)..where((t) => t.id.equals(sourceId))).write(
          CalendarSourcesCompanion(lastSyncAt: Value(DateTime.now())),
        );

        await db.finishSyncLog(
          logId: logId,
          status: 'not_modified',
          httpStatus: 304,
          itemCount: 0,
          message: 'Not Modified',
        );
        return;
      }

      final etag = resp.headers.value('etag');
      final lastModified = resp.headers.value('last-modified');

      final raw = resp.data ?? '';
      final normalized = _ics.normalize(raw);

      final imported = _ics.importWithUid(normalized);

      await db.transaction(() async {
        await db.batch((b) {
          b.insertAllOnConflictUpdate(
            db.events,
            imported.map((item) => item.data.copyWith(
              sourceId: Value(sourceId),
              externalUid: Value(item.uid),
            )).toList(),
          );
        });
      });


      await (db.update(db.calendarSources)..where((t) => t.id.equals(sourceId))).write(
        CalendarSourcesCompanion(
          etag: Value(etag),
          lastModified: Value(lastModified),
          lastSyncAt: Value(DateTime.now()),
        ),
      );

      await db.finishSyncLog(
        logId: logId,
        status: 'success',
        httpStatus: resp.statusCode,
        itemCount: imported.length,
        message: 'OK',
      );
    } catch (e) {
      await db.finishSyncLog(
        logId: logId,
        status: 'failed',
        message: e.toString(),
      );
      rethrow;
    }
  }
}
