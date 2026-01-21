import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_db.dart';

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'calendarx.db'));
    // ✅ 后台 isolate 打开数据库，避免主线程卡顿
    return NativeDatabase.createInBackground(file);
  });
}

final appDbProvider = Provider<AppDb>((ref) {
  final db = AppDb(_openConnection());
  ref.onDispose(db.close);
  return db;
});
