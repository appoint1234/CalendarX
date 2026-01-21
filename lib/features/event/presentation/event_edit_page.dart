import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;


import '../../../core/db/app_db.dart';
import '../../../core/db/db_provider.dart';
import 'package:calendar/core/notify/alarm_reminder.dart';


class EventEditPage extends ConsumerStatefulWidget {
  const EventEditPage({
    super.key,
    this.eventId,
    this.initialStart, 
  });

  final int? eventId;
  final DateTime? initialStart;

  @override
  ConsumerState<EventEditPage> createState() => _EventEditPageState();
}

class _EventEditPageState extends ConsumerState<EventEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(hours: 1));
  bool _allDay = false;

  int? _remindBeforeMin; // null=不提醒

  static const List<int?> _remindOptions = <int?>[
    null,
    0,
    5,
    10,
    15,
    30,
    60,
    120,
    1440,
  ];

  String _remindLabel(int? m) {
    if (m == null) return "不提醒";
    if (m == 0) return "准时";
    if (m < 60) return "提前 $m 分钟";
    if (m == 60) return "提前 1 小时";
    if (m < 1440) return "提前 ${m ~/ 60} 小时";
    return "提前 1 天";
  }

  final _fmtDateTime = DateFormat('yyyy-MM-dd HH:mm');
  final _fmtDate = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();

    final init = widget.initialStart;
    if (widget.eventId == null) {
      final now = DateTime.now();
      final base = init ?? now;

      final isToday =
          base.year == now.year && base.month == now.month && base.day == now.day;

      DateTime start;
      if (isToday) {
        final roundedNow = _ceilToMinutes(now, 5); 
        start = DateTime(base.year, base.month, base.day, roundedNow.hour, roundedNow.minute);
      } else {
        start = DateTime(base.year, base.month, base.day, 9, 0);
      }

      _start = start;
      _end = start.add(const Duration(hours: 1));

      // 防止跨天（比如 23:30 + 1h）
      if (_end.day != _start.day) {
        _end = DateTime(_start.year, _start.month, _start.day, 23, 59);
      }
    }
    _loadIfEdit();
  }

  DateTime _ceilToMinutes(DateTime dt, int interval) {
    var d = dt;
    // 有秒/毫秒就先进位到下一分钟，避免“刚好整点但已经过去了”
    if (d.second != 0 || d.millisecond != 0 || d.microsecond != 0) {
      d = d.add(const Duration(minutes: 1));
    }
    final mod = d.minute % interval;
    final add = mod == 0 ? 0 : (interval - mod);
    final r = d.add(Duration(minutes: add));
    return DateTime(r.year, r.month, r.day, r.hour, r.minute);
  }

  Future<void> _loadIfEdit() async {
    final id = widget.eventId;
    if (id == null) return;

    final db = ref.read(appDbProvider);
    final e = await db.getEvent(id);
    if (!mounted || e == null) return;

    setState(() {
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description ?? '';
      _start = e.startAt;
      _end = e.endAt;
      _allDay = e.allDay;
      _remindBeforeMin = e.remindBeforeMinutes;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  DateTime _trimToMinute(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);

  Future<DateTime?> _pickWheelDateTime({
    required DateTime initial,
    required bool allDay,
  }) async {
    DateTime temp = initial;

    final picked = await showModalBottomSheet<DateTime?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final h = MediaQuery.of(ctx).size.height;

        return SafeArea(
          child: SizedBox(
            height: (h * 0.42).clamp(280, 360).toDouble(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(null),
                        child: const Text("取消"),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(temp),
                        child: Text("确定", style: TextStyle(color: cs.primary)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: Theme.of(ctx).brightness,
                      primaryColor: cs.primary,
                    ),
                    child: CupertinoDatePicker(
                      mode: allDay
                          ? CupertinoDatePickerMode.date
                          : CupertinoDatePickerMode.dateAndTime,
                      use24hFormat: true, // ✅ 24小时制
                      minuteInterval: 1, // ✅ 精确到分钟（无秒）
                      initialDateTime: initial,
                      onDateTimeChanged: (v) => temp = v,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null) return null;

    if (allDay) {
      return DateTime(picked.year, picked.month, picked.day);
    }
    return _trimToMinute(picked);
  }

  void _fixEndIfNeeded() {
    if (!_end.isAfter(_start)) {
      _end = _start.add(const Duration(hours: 1));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_allDay) {
      final s = DateTime(_start.year, _start.month, _start.day);
      _start = s;
      _end = s.add(const Duration(days: 1));
    }

    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("结束时间必须晚于开始时间")),
      );
      return;
    }

    final db = ref.read(appDbProvider);

    final data = EventsCompanion(
      title: Value(_titleCtrl.text.trim()),
      description: Value(_descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
      startAt: Value(_start),
      endAt: Value(_end),
      allDay: Value(_allDay),
      remindBeforeMinutes: Value(_remindBeforeMin),
    );

    int eventId;

    try {
      if (widget.eventId == null) {
        eventId = await db.createEvent(data);
      } else {
        eventId = widget.eventId!;
        await db.updateEventById(eventId, data);
      }

      //  调度通知（失败也不影响保存/退出）
      try {
        await AlarmReminder.cancelEventReminder(eventId);

        final remind = _remindBeforeMin;
        if (remind != null) {
          final now = DateTime.now();
          final fireAt = _start.subtract(Duration(minutes: remind));

          // 如果 fireAt 已经过了
          final scheduledAt = fireAt.isAfter(now)
              ? fireAt
              : now.add(const Duration(seconds: 2));

          await AlarmReminder.scheduleEventReminder(
            eventId: eventId,
            title: _titleCtrl.text.trim(),
            body: "即将开始：${_fmtDateTime.format(_start)}",
            fireAtLocal: fireAt,
          );
}
      } catch (e, st) {

        print("schedule notification failed: $e\n$st");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("提醒设置失败，但日程已保存")),
          );
        }
      }
    } finally {
      if (!mounted) return;
      Navigator.of(context).pop(true); //  无论提醒成功与否都退出
    }
  }


  Future<void> _delete() async {
    final id = widget.eventId;
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("删除日程？"),
        content: const Text("删除后不可恢复。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("删除")),
        ],
      ),
    );

    if (ok != true) return;

    final db = ref.read(appDbProvider);
    await AlarmReminder.cancelEventReminder(id);
    await db.deleteEventById(id);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _card({required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(children: children),
      ),
    );
  }

  Widget _kvRow({
    required String label,
    required Widget value,
    VoidCallback? onTap,
  }) {
    final row = Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 8),
        Expanded(child: Align(alignment: Alignment.centerRight, child: value)),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, size: 18, color: Colors.grey[600]),
      ],
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.eventId != null;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(isEdit ? "编辑日程" : "新建日程"),
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("取消"),
        ),
        leadingWidth: 72,
        actions: [
          if (isEdit)
            IconButton(
              tooltip: "删除",
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            onPressed: _save,
            child: const Text("完成"),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            // 1) 标题 / 备注
            _card(
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: "标题 *",
                    border: UnderlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? "请输入标题" : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: "备注",
                    border: UnderlineInputBorder(),
                    isDense: true,
                    alignLabelWithHint: true,
                  ),
                  minLines: 1, 
                  maxLines: 3,
                ),
              ],
            ),

            // 2) 时间（滚轮 24h）
            _card(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allDay,
                  title: const Text("全天"),
                  onChanged: (v) {
                    setState(() {
                      _allDay = v;
                      if (_allDay) {
                        _start = DateTime(_start.year, _start.month, _start.day);
                        _end = DateTime(_start.year, _start.month, _start.day).add(const Duration(days: 1));
                      } else {
                        _start = DateTime(_start.year, _start.month, _start.day, 9, 0);
                        _end = _start.add(const Duration(hours: 1));
                      }
                    });
                  },
                ),
                const Divider(height: 10),
                _kvRow(
                  label: "开始",
                  value: Text(_allDay ? _fmtDate.format(_start) : _fmtDateTime.format(_start)),
                  onTap: () async {
                    final dt = await _pickWheelDateTime(initial: _start, allDay: _allDay);
                    if (dt == null) return;
                    setState(() {
                      _start = dt;
                      _fixEndIfNeeded();
                    });
                  },
                ),
                const Divider(height: 1),
                _kvRow(
                  label: "结束",
                  value: Text(_allDay ? _fmtDate.format(_end) : _fmtDateTime.format(_end)),
                  onTap: () async {
                    final dt = await _pickWheelDateTime(initial: _end, allDay: _allDay);
                    if (dt == null) return;
                    setState(() {
                      _end = dt;
                      _fixEndIfNeeded();
                    });
                  },
                ),
              ],
            ),

            // 3) 提醒
            _card(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 72, child: Text("提醒")),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          isExpanded: true,
                          value: _remindBeforeMin,
                          items: _remindOptions
                              .map((m) => DropdownMenuItem<int?>(
                                    value: m,
                                    child: Text(_remindLabel(m)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _remindBeforeMin = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: FilledButton(
                onPressed: _save,
                child: const Text("保存"),
                
              ),
              
            ),
          ],
        ),
      ),
    );
  }
}
