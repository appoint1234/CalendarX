import 'dart:io';

import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../event/presentation/event_edit_page.dart';
import '../../event/data/event_providers.dart';
import '../../../core/db/app_db.dart';
import 'calendar_state.dart';
import '../../ics/ics_export.dart';
import '../../ics/ics_import.dart';
import '../../subscription/subscription_page.dart';
import '../../../core/lunar/lunar_utils.dart';
import 'calendar_search_page.dart';
import 'package:flutter/foundation.dart';
import '../../../core/db/db_provider.dart';



class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final EventController _events;

  // 记住当前三视图各自的“锚点日期”（用于跳转 & 标题）
  DateTime _monthAnchor = DateTime.now();
  DateTime _weekAnchor = DateTime.now();
  DateTime _dayAnchor = DateTime.now();

  static const double _kDayHeightPerMinute = 0.7; // 与 DayView 默认一致，建议显式写死
  static const double _kWeekHeightPerMinute = 1.0; // 与 WeekView 默认一致

  double _dayScrollOffset = 0.0;
  double _weekScrollOffset = 0.0;

  double _calcScrollOffset(
    DateTime start,
    double heightPerMinute, {
    int contextMinutes = 60,
  }) {
    final minutes = start.hour * 60 + start.minute;
    final target = (minutes - contextMinutes) * heightPerMinute; // 往上留 1 小时上下文
    return target < 0 ? 0 : target;
  }

  // 月视图：当前选中日期 & 该日事件（用于底部“日程面板”）
  DateTime _monthSelected = DateTime.now();
  List<CalendarEventData<Object?>> _monthSelectedEvents = const [];

  void _setVisibleDateSafe(DateTime d) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(visibleDateProvider.notifier).state = d;
    });
  }

  void _setTabSafe(CalendarTab tab) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(calendarTabProvider.notifier).state = tab;
    });
  }

  
  //性能测试
  Future<void> _runPerfTest(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDbProvider);

    const seedCount = 5000;

    // 1) 造数据耗时
    final seedSw = Stopwatch()..start();
    await db.seedRandomEvents(
      count: seedCount,
      fromDay: DateTime.now().subtract(const Duration(days: 14)),
      spanDays: 60,
    );
    seedSw.stop();

    // 2) 周范围查询耗时
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final weekEnd = weekStart.add(const Duration(days: 7));

    final querySw = Stopwatch()..start();
    final weekEvents = await db.watchEventsInRange(weekStart, weekEnd).first; // 复用已有查询
    querySw.stop();

    // 3) 搜索耗时
    int searchMs = -1;
    int searchCount = 0;
    try {
      final searchSw = Stopwatch()..start();
      final res = await db.searchEvents(
        keyword: 'Perf-',
        from: weekStart,
        to: weekEnd,
        limit: 200,
      );
      searchSw.stop();
      searchMs = searchSw.elapsedMilliseconds;
      searchCount = res.length;
    } catch (_) {
    }

    if (!context.mounted) return;

    final content = StringBuffer()
      ..writeln('造数据：$seedCount 条，用时 ${seedSw.elapsedMilliseconds} ms')
      ..writeln('周范围查询：${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}')
      ..writeln('返回 ${weekEvents.length} 条，用时 ${querySw.elapsedMilliseconds} ms');
    if (searchMs >= 0) {
      content.writeln('搜索（keyword="Perf-"，limit=200）：返回 $searchCount 条，用时 $searchMs ms');
    } else {
      content.writeln('搜索耗时：未统计（searchEvents 不可用或签名不同）');
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('性能压测结果'),
        content: Text(content.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }


  void _jumpToEvent(Event e) {
    final day = DateTime(e.startAt.year, e.startAt.month, e.startAt.day);

    setState(() {
      _monthAnchor = DateTime(day.year, day.month, 1);
      _monthSelected = day;

      _weekAnchor = _startOfWeek(day);
      _dayAnchor = day;

      _dayScrollOffset = _calcScrollOffset(e.startAt, _kDayHeightPerMinute);
      _weekScrollOffset = _calcScrollOffset(e.startAt, _kWeekHeightPerMinute);
    });

    _setVisibleDateSafe(day);
    _setTabSafe(CalendarTab.day);
    _tabs.animateTo(2);
  }

  @override
  void initState() {
    super.initState();
    _events = EventController();
    _tabs = TabController(length: 3, vsync: this);

    final now = DateTime.now();
    _monthAnchor = DateTime(now.year, now.month, 1);
    _monthSelected = DateTime(now.year, now.month, now.day);
    _setVisibleDateSafe(now);

    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      ref.read(calendarTabProvider.notifier).state = switch (_tabs.index) {
        0 => CalendarTab.month,
        1 => CalendarTab.week,
        _ => CalendarTab.day,
      };
      // 切换 tab 时同步标题日期
      final d = switch (_tabs.index) {
        0 => _monthAnchor,
        1 => _weekAnchor,
        _ => _dayAnchor,
      };
      _setVisibleDateSafe(d);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _events.dispose();
    super.dispose();
  }

  static const double _kTimeLineWidth = 56; // ✅ 跟 WeekView 左侧时间轴宽度保持一致
  static const double _kWeekHeaderHeight = 46;

  String _title(DateTime d, CalendarTab tab) {
    String two(int x) => x.toString().padLeft(2, '0');
    return switch (tab) {
      CalendarTab.month => "${d.year}-${two(d.month)}",
      CalendarTab.week ||
      CalendarTab.day => "${d.year}-${two(d.month)}-${two(d.day)}",
    };
  }

  DateTimeRange _monthRange(DateTime anchor) {
    final first = DateTime(anchor.year, anchor.month, 1);
    final nextMonth = DateTime(anchor.year, anchor.month + 1, 1);
    // 给一点缓冲，避免跨月显示不全
    return DateTimeRange(
      start: first.subtract(const Duration(days: 7)),
      end: nextMonth.add(const Duration(days: 7)),
    );
  }

  DateTimeRange _weekRange(DateTime anchor) {
    // 以周一为周起点
    final weekday = anchor.weekday; // 1..7 (Mon..Sun)
    final monday = DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
    ).subtract(Duration(days: weekday - 1));
    final sundayNext = monday.add(const Duration(days: 7));
    return DateTimeRange(start: monday, end: sundayNext);
  }

  DateTimeRange _dayRange(DateTime anchor) {
    final start = DateTime(anchor.year, anchor.month, anchor.day);
    final end = start.add(const Duration(days: 1));
    return DateTimeRange(start: start, end: end);
  }

  /// drift Event -> calendar_view 的事件模型
  CalendarEventData<Object> _toCalendarEvent(Event e) {
    return CalendarEventData<Object>(
      date: e.startAt,
      startTime: e.startAt,
      endTime: e.endAt,
      title: e.title,
      description: e.description,
      event: e.id, // 把 id 塞进去，点事件时取出来用
    );
  }

  void _syncEventsToController(List<Event> list) {
    // 重新渲染：先清空再加（MVP 简单可靠）
    _events.removeWhere((_) => true);
    for (final e in list) {
      _events.add(_toCalendarEvent(e));
    }

    //  关键：同步刷新“底部当天列表”，这样新增/编辑后马上出现
    final selectedDay = DateTime(
      _monthSelected.year,
      _monthSelected.month,
      _monthSelected.day,
    );
    final start = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );
    final end = start.add(const Duration(days: 1));

    final selected =
        list
            .where((e) => !e.startAt.isBefore(start) && e.startAt.isBefore(end))
            .map(_toCalendarEvent)
            .toList()
          ..sort((a, b) => a.startTime!.compareTo(b.startTime!));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _monthSelectedEvents = selected);
    });
  }

  void _goToday() {
    final now = DateTime.now();
    ref.read(visibleDateProvider.notifier).state = now;

    switch (ref.read(calendarTabProvider)) {
      case CalendarTab.month:
        setState(() => _monthAnchor = now);
        break;
      case CalendarTab.week:
        setState(() => _weekAnchor = now);
        break;
      case CalendarTab.day:
        setState(() => _dayAnchor = now);
        break;
    }
    setState(() {});
  }

  void _openDay(DateTime date) {
    _dayAnchor = date;
    _setVisibleDateSafe(date);
    _setTabSafe(CalendarTab.day);
    _tabs.animateTo(2);
    setState(() {});
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _monthTitle(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}";

  String _weekdayLabel(int index) {
    // startDay = Monday
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return labels[index % 7];
  }

  DateTime _startOfWeek(DateTime d) {
    // 以周一为一周开始
    final dd = DateTime(d.year, d.month, d.day);
    final diff = dd.weekday - DateTime.monday; // monday=1
    return dd.subtract(Duration(days: diff));
  }

  String _dayTitle(DateTime d) {
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _weekTitle(DateTime anchor) {
    final s = _startOfWeek(anchor);
    final e = s.add(const Duration(days: 6));
    if (s.year != e.year) {
      return "${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')} ~ "
          "${e.year}-${e.month.toString().padLeft(2, '0')}-${e.day.toString().padLeft(2, '0')}";
    }
    return "${s.month}月${s.day}日 ~ ${e.month}月${e.day}日";
  }

  void _changeWeek(int deltaWeeks) {
    final next = _startOfWeek(_weekAnchor.add(Duration(days: 7 * deltaWeeks)));
    setState(() => _weekAnchor = next);
    _setVisibleDateSafe(next);
  }

  Future<void> _changeMonth(int delta) async {
    final next = DateTime(_monthAnchor.year, _monthAnchor.month + delta, 1);
    setState(() {
      _monthAnchor = next;
      _monthSelected = next; // 默认选中当月 1 号
      _monthSelectedEvents = const [];
    });
    _setVisibleDateSafe(next);
  }

  Future<void> _openEventEdit(int eventId) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EventEditPage(eventId: eventId)),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已更新")));
    }
  }

  Widget _monthAgendaPanel() {
    final cs = Theme.of(context).colorScheme;
    final day = DateTime(
      _monthSelected.year,
      _monthSelected.month,
      _monthSelected.day,
    );
    final weekday = DateFormat('E', 'zh_CN').format(day); // 周一/周二...
    final lunar = LunarUtils.monthDayText(day);
    final h = MediaQuery.of(context).size.height;

    final items = List<CalendarEventData<Object?>>.from(_monthSelectedEvents)
      ..sort((a, b) {
        final sa = a.startTime;
        final sb = b.startTime;

        // null 排到最后
        if (sa == null && sb == null) return 0;
        if (sa == null) return 1;
        if (sb == null) return -1;

        return sa.compareTo(sb);
      });

    String timeText(CalendarEventData<Object?> e) {
      final s = e.startTime;
      final t = e.endTime;

      if (s == null || t == null) return "--:-- - --:--";

      final fmt = DateFormat('HH:mm');
      return "${fmt.format(s)} - ${fmt.format(t)}";
    }

    return Container(
      height: (h * 0.28).clamp(180, 260).toDouble(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.45),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 选中日期 + 农历（在日历下方显示）
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${day.month}月${day.day}日  $weekday",
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lunar,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: "新增日程",
                onPressed: () async {
                  final ok = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          EventEditPage(initialStart: _monthSelected),
                    ),
                  );
                  if (ok == true && mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("已保存")));
                  }
                },
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      "暂无日程",
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      primary: false,
                      physics: const BouncingScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (_, i) {
                        final e = items[i];
                        final id = e.event as int;
                        return InkWell(
                          onTap: () => _openEventEdit(id),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        timeText(e),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.grey[700]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showEventSheet(CalendarEventData<Object?> e) {
    final start = e.startTime;
    final end = e.endTime;
    final fmt = DateFormat('HH:mm');

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return InkWell(
          //  再点一下弹窗主体也能进入编辑
          onTap: () {
            Navigator.pop(ctx);
            final id = e.event as int;
            _openEventEdit(id);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  (start != null && end != null)
                      ? '${fmt.format(start)} - ${fmt.format(end)}'
                      : '--:-- - --:--',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final id = e.event as int;
                      _openEventEdit(id);
                    },
                    child: const Text('编辑'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _eventTile(List<CalendarEventData<Object?>> events) {
    final e = events.first;
    final base = Theme.of(context).colorScheme.primary;
    final bg = base.withOpacity(0.18); 

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: base, width: 3)),
      ),
      child: Text(
        e.title, // ✅ 显示标题
        maxLines: 2, // ✅ 最多两行
        overflow: TextOverflow.ellipsis, // ✅ 超出省略号
        style: const TextStyle(fontSize: 12, color: Colors.black87),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(calendarTabProvider);
    final visible = ref.watch(visibleDateProvider);

    final range = switch (tab) {
      CalendarTab.month => _monthRange(_monthAnchor),
      CalendarTab.week => _weekRange(_weekAnchor),
      CalendarTab.day => _dayRange(_dayAnchor),
    };

    final asyncEvents = ref.watch(eventsInRangeProvider(range));
    final isLoading = asyncEvents.isLoading;
    asyncEvents.whenData(_syncEventsToController);

    return CalendarControllerProvider(
      controller: _events,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("CalendarX · ${_title(visible, tab)}"),
              Text(
                LunarUtils.monthDayText(visible),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () async {
                final row = await Navigator.of(context).push<EventSearchRow>(
                  MaterialPageRoute(builder: (_) => const CalendarSearchPage()),
                );
                if (row == null) return;

                _jumpToEvent(row.event);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已跳转：${row.event.title}')),
                  );
                }
              },
            ),
            TextButton(onPressed: _goToday, child: const Text("Today")),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'export') {
                  final path = await IcsExport.exportAll(
                    ref,
                  ); 
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '导出成功：${path.split(Platform.pathSeparator).last}',
                      ),
                      action: SnackBarAction(label: '知道了', onPressed: () {}),
                    ),
                  );
                } else if (v == 'import') {
                  await IcsImport.importFromLocalExports(context, ref);
                } else if (v == 'subs') {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SubscriptionPage()),
                  );
                } else if (v == 'debugPerf') {
                  await _runPerfTest(context, ref);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'export', child: Text('导出 ICS')),
                PopupMenuItem(value: 'import', child: Text('导入 ICS')),
                PopupMenuItem(value: 'subs', child: Text('订阅管理')),
                PopupMenuItem(value: 'debugPerf', child: Text('性能压测')),
              ],
              icon: const Icon(Icons.more_vert),
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: "月"),
              Tab(text: "周"),
              Tab(text: "日"),
            ],
          ),
        ),

        body: TabBarView(
          controller: _tabs,
          children: [
            // ===== 月 =====
            Column(
              children: [
                // 顶部：月份切换
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                  child: Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          _monthTitle(_monthAnchor),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),

                // 月视图主体
                Expanded(
                  child: MonthView(
                    key: ValueKey(
                      'month-${_monthAnchor.year}-${_monthAnchor.month}',
                    ),
                    controller: _events,
                    minMonth: DateTime(2000, 1),
                    maxMonth: DateTime(2100, 12),
                    initialMonth: DateTime(
                      _monthAnchor.year,
                      _monthAnchor.month,
                      1,
                    ),

                    // 只显示当前月
                    hideDaysNotInMonth: true,

                    //  关掉 MonthView 自带的大边框/网格线
                    showBorder: false,
                    showWeekTileBorder: false,
                    borderSize: 0,
                    borderColor: Colors.transparent,

                    //  别那么“瘦高”：让格子更接近正方形
                    cellAspectRatio: 0.95,

                    // 取消 MonthView 自带的“中间月份切换栏”
                    headerBuilder: (_) => const SizedBox.shrink(),
                    headerStyle: const HeaderStyle(
                      headerTextStyle: TextStyle(fontSize: 0),
                      headerPadding: EdgeInsets.zero,
                      headerMargin: EdgeInsets.zero,
                      leftIconConfig: null,
                      rightIconConfig: null,
                      decoration: BoxDecoration(),
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                    ),

                    // ✅ 取消 MonthView 自带 weekday（我们上面自己画了）
                    weekDayBuilder: (index) {
                      const labels = ['一', '二', '三', '四', '五', '六', '日'];
                      final isWeekend = index >= 5;
                      final cs = Theme.of(context).colorScheme;

                      return SizedBox(
                        height: 28, // ✅ 更紧凑
                        child: Center(
                          child: Text(
                            labels[index],
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isWeekend
                                      ? Theme.of(context).hintColor
                                      : cs.onSurface,
                                ),
                          ),
                        ),
                      );
                    },

                    //  cell：日期（上）+ 农历（下），同一竖直线居中；有日程显示一个点
                    cellBuilder:
                        (date, events, isToday, isInMonth, hideDaysNotInMonth) {
                          if (!isInMonth) return const SizedBox.shrink();

                          final cs = Theme.of(context).colorScheme;
                          final lunar = LunarUtils.shortLabel(date);

                          final selected = _isSameDay(date, _monthSelected);

                          return Padding(
                            padding: const EdgeInsets.all(3),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? cs.primary
                                      : Theme.of(context).dividerColor,
                                  width: selected ? 1.2 : 0.8,
                                ),
                                color: selected
                                    ? cs.primaryContainer.withOpacity(0.65)
                                    : isToday
                                    ? cs.primaryContainer.withOpacity(0.25)
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${date.day}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: selected
                                                    ? cs.onPrimaryContainer
                                                    : null,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          lunar,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontSize: 10,
                                                height: 1,
                                                color: Colors.grey[700],
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (events.isNotEmpty)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: cs.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },

                    // 翻页（月切换）同步顶部标题
                    onPageChange: (date, _) {
                      final firstOfMonth = DateTime(date.year, date.month, 1);
                      setState(() {
                        _monthAnchor = firstOfMonth;
                        _monthSelected = firstOfMonth;
                        _monthSelectedEvents = const [];
                      });
                      _setVisibleDateSafe(firstOfMonth);
                    },

                    // 点击日期：选中 + 底部展示当天日程
                    onCellTap: (events, date) {
                      final d = DateTime(date.year, date.month, date.day);
                      setState(() {
                        _monthSelected = d;
                        _monthSelectedEvents =
                            List<CalendarEventData<Object?>>.from(events);
                      });
                      _setVisibleDateSafe(d);
                    },

                    onDateLongPress: (date) => _openDay(date),

                    onEventTap: (event, date) async {
                      final id = event.event as int;
                      await _openEventEdit(id);
                    },
                  ),
                ),

                // 底部：当天日程
                _monthAgendaPanel(),
              ],
            ),

            // ===== 周 =====
            Column(
              children: [
                // 顶部：周范围
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                  child: Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        onPressed: () => _changeWeek(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          _weekTitle(_weekAnchor),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        onPressed: () => _changeWeek(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                  ), //  必须跟 WeekView 外层一致
                  child: SizedBox(
                    height: 92,
                    child: Row(
                      children: [
                        const SizedBox(
                          width: _kTimeLineWidth,
                        ), //  关键：给左侧时间轴留位置，才会对齐格子
                        ...List.generate(7, (i) {
                          final isWeekend = i >= 5;
                          final day = _startOfWeek(
                            _weekAnchor,
                          ).add(Duration(days: i)); //  本周日期
                          final cs = Theme.of(context).colorScheme;
                          return Expanded(
                            child: Builder(
                              builder: (context) {
                                final cs = Theme.of(context).colorScheme;
                                final lunar = LunarUtils.shortLabel(day);
                                final selected = _isSameDay(
                                  day,
                                  _monthSelected,
                                );
                                final isToday = _isSameDay(day, DateTime.now());

                                //  判断这一天是否有事件（用于右上角小点）
                                final hasEvents = _events.events.any((e) {
                                  final st = e.startTime;
                                  return st != null && _isSameDay(st, day);
                                });

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 星期
                                    Text(
                                      _weekdayLabel(i),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: isWeekend
                                                ? Theme.of(context).hintColor
                                                : cs.onSurface,
                                          ),
                                    ),
                                    const SizedBox(height: 6),

                                    // ✅ 这块就是“月视图 cellBuilder”同款外观
                                    Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          setState(() => _monthSelected = day);
                                          _setVisibleDateSafe(day);
                                        },
                                        child: Container(
                                          height: 46, // 周头更矮一点，避免溢出
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: selected
                                                  ? cs.primary
                                                  : Theme.of(
                                                      context,
                                                    ).dividerColor,
                                              width: selected ? 1.2 : 0.8,
                                            ),
                                            color: selected
                                                ? cs.primaryContainer
                                                      .withOpacity(0.65)
                                                : isToday
                                                ? cs.primaryContainer
                                                      .withOpacity(0.25)
                                                : null,
                                          ),
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '${day.day}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleSmall
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: selected
                                                                ? cs.onPrimaryContainer
                                                                : null,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      lunar,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            fontSize: 10,
                                                            height: 1,
                                                            color: Colors
                                                                .grey[700],
                                                          ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ClipRect(
                      child: Transform.translate(
                        //  这个值就是“all-day 区域高度”
                        offset: const Offset(0, -48),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 48),
                          child: WeekView(
                            key: ValueKey(
                              'week-${_weekAnchor.year}-${_weekAnchor.month}-${_weekAnchor.day}',
                            ),
                            controller: _events,
                            initialDay: _weekAnchor,
                            showLiveTimeLineInAllDays: false,
                            liveTimeIndicatorSettings:
                                LiveTimeIndicatorSettings.none(),
                            weekPageHeaderBuilder: (date, pageController) =>
                                const SizedBox.shrink(),
                            weekDayBuilder: (_) => const SizedBox.shrink(),
                            timeLineWidth: _kTimeLineWidth,

                            heightPerMinute: _kWeekHeightPerMinute,
                            scrollOffset: _weekScrollOffset,
                            keepScrollOffset: true,
                            startHour: 0,
                            endHour: 24,
                            timeLineBuilder: (date) {
                              final label = DateFormat('HH:mm').format(date);
                              return Transform.translate(
                                offset: const Offset(0, -6),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              );
                            },

                            eventTileBuilder:
                                (date, events, boundary, start, end) {
                                  return _eventTile(events);
                                },

                            fullDayHeaderTitle: '',
                            fullDayEventBuilder: (events, date) =>
                                const SizedBox.shrink(),

                            onPageChange: (date, _) {
                              final s = _startOfWeek(date);
                              setState(() => _weekAnchor = s);
                              _setVisibleDateSafe(date);
                            },

                            onDateLongPress: (date) => _openDay(date),

                            onEventTap: (events, date) async {
                              if (events.isEmpty) return;
                              _showEventSheet(events.first);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ===== 日 =====
            Column(
              children: [
                // 顶部：日期
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                  child: Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        onPressed: () {
                          setState(
                            () => _dayAnchor = _dayAnchor.subtract(
                              const Duration(days: 1),
                            ),
                          );
                          _setVisibleDateSafe(_dayAnchor);
                        },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          _dayTitle(_dayAnchor), // 下面第 2 步会让你加这个方法
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        onPressed: () {
                          setState(
                            () => _dayAnchor = _dayAnchor.add(
                              const Duration(days: 1),
                            ),
                          );
                          _setVisibleDateSafe(_dayAnchor);
                        },
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DayView(
                      key: ValueKey(
                        'day-${_dayAnchor.year}-${_dayAnchor.month}-${_dayAnchor.day}',
                      ),
                      controller: _events,
                      initialDay: _dayAnchor,
                      showLiveTimeLineInAllDays: false,
                      liveTimeIndicatorSettings:
                          LiveTimeIndicatorSettings.none(),
                      heightPerMinute: _kDayHeightPerMinute,
                      scrollOffset: _dayScrollOffset,
                      keepScrollOffset: true,

                      // ✅ 隐藏 DayView 自带 header
                      dayTitleBuilder: (date) => const SizedBox.shrink(),

                      // ✅ 24 小时制
                      startHour: 0,
                      endHour: 24,
                      timeLineWidth: _kTimeLineWidth, 
                      timeLineBuilder: (date) {
                        final label = DateFormat('HH:mm').format(date);
                        return Transform.translate(
                          offset: const Offset(0, -6),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Text(
                              label,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        );
                      },

                      eventTileBuilder: (date, events, boundary, start, end) {
                        return _eventTile(events);
                      },

                      onPageChange: (date, _) {
                        setState(() => _dayAnchor = date);
                        _setVisibleDateSafe(date);
                      },
                      onEventTap: (events, date) async {
                        if (events.isEmpty) return;
                        _showEventSheet(events.first);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: (tab == CalendarTab.month)
            ? null
            : FloatingActionButton(
                onPressed: () async {
                  final ok = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          EventEditPage(initialStart: _monthSelected),
                    ),
                  );
                  if (ok == true && mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("已保存")));
                  }
                },
                child: const Icon(Icons.add),
              ),
      ),
    );
  }
}
