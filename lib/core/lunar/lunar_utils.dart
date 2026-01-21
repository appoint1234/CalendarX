import 'package:lunar/lunar.dart';

class LunarUtils {
  static final Map<int, String> _shortCache = {};

  static int _key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// 月视图格子里显示的短文本（节日 > 其它节日 > 节气 > 初一显示月份 > 否则显示“初二/廿三…”）
  static String shortLabel(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final k = _key(d);

    final cached = _shortCache[k];
    if (cached != null) return cached;

    // 简单防爆：缓存太大就清一次
    if (_shortCache.length > 900) _shortCache.clear();

    final lunar = Lunar.fromDate(d);

    final festivals = lunar.getFestivals();
    if (festivals.isNotEmpty) {
      return _shortCache[k] = festivals.first;
    }

    final other = lunar.getOtherFestivals();
    if (other.isNotEmpty) {
      return _shortCache[k] = other.first;
    }

    final jieQi = lunar.getJieQi(); // 没有则通常是空串
    if (jieQi.isNotEmpty) {
      return _shortCache[k] = jieQi;
    }

    if (lunar.getDay() == 1) {
      return _shortCache[k] = lunar.getMonthInChinese(); // 初一显示“正月/二月…”
    }

    return _shortCache[k] = lunar.getDayInChinese(); // “初二/廿三…”
  }

  /// AppBar/详情里显示用：如 “腊月十六”
  static String monthDayText(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final lunar = Lunar.fromDate(d);
    return '${lunar.getMonthInChinese()}${lunar.getDayInChinese()}';
  }
}
