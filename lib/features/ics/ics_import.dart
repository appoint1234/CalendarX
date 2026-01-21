import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/db/db_provider.dart';
import 'ics_service.dart';
import 'package:path_provider/path_provider.dart';


class IcsImport {
  static Future<void> importFromLocalExports(BuildContext context, WidgetRef ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final exportsDir = Directory('${dir.path}/exports');
  if (!await exportsDir.exists()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本地没有导出文件（exports 目录不存在）')),
    );
    return;
  }

  final files = exportsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.ics'))
      .toList()
    ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

  if (files.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本地没有导出过 .ics 文件')),
    );
    return;
  }
  final picked = await showDialog<File>(
    context: context,
    builder: (_) => SimpleDialog(
      title: const Text('选择要导入的 ICS'),
      children: [
        for (final f in files.take(20))
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, f),
            child: Text(f.path.split(Platform.pathSeparator).last),
          ),
      ],
    ),
  );
  if (picked == null) return;

  final raw = await picked.readAsString();
  final list = IcsService().importFromIcs(raw);

  final db = ref.read(appDbProvider);
  for (final c in list) {
    await db.createEvent(c);
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('已导入 ${list.length} 条事件（${picked.path.split(Platform.pathSeparator).last}）')),
  );
}

}
