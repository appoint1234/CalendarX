import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/db/db_provider.dart';
import '../../core/db/app_db.dart';
import 'ics_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class IcsExport {
  static Future<String> exportAll(WidgetRef ref) async {
    final db = ref.read(appDbProvider);
    final List<Event> all = await db.getAllEvents();
    final ics = IcsService().exportToIcs(events: all);
    final dir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${dir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }

    final file = File('${exportsDir.path}/calendarx_${DateTime.now().millisecondsSinceEpoch}.ics');
    await file.writeAsString(ics, flush: true);
    return file.path;
  }
}
