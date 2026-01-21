import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_db.dart';
import 'package:flutter/material.dart';
import '../../../core/db/db_provider.dart';

/// 传入一个 (from,to) 范围，返回这个范围内的事件流
final eventsInRangeProvider =
    StreamProvider.family<List<Event>, DateTimeRange>((ref, range) {
  final db = ref.watch(appDbProvider);
  return db.watchEventsInRange(range.start, range.end);
});
