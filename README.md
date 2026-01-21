# CalendarX｜Android 日历 App（Flutter + Riverpod + Drift）

CalendarX 是一款面向 Android 的日历应用，提供 **月/周/日三视图**、日程管理、提醒通知、**农历显示**，并支持 **ICS 导入/导出** 与 **ICS 订阅增量同步（ETag/Last-Modified）**。
项目以“像手机系统日历”的交互体验为目标，强调 **离线优先、同步稳定、可检索可定位、可观测可测试**。

---

## 功能特性

### 1) 日历视图 & 交互

- 月 / 周 / 日三视图（基于 `calendar_view`）
- 周/日视图：左侧 24 小时制时间轴，事件块轻量样式（标题省略、浅色背景）
- 事件交互：点击预览弹窗 → 二次点击进入编辑（贴近系统日历）
- 顶部 “Today” 一键回到今天（月/周/日视图统一返回当前日期）

### 2) 日程管理

- 新建 / 编辑 / 删除日程
- 字段：标题、备注、开始/结束时间、全天、提醒（提前 N 分钟）
- 全天事件规则：开启全天时 `00:00 ~ 次日 00:00`；关闭全天可恢复原时间（不重置默认值）

### 3) 搜索 + 筛选 + 跳转定位（亮点）

- 全局搜索：标题 / 备注 / 订阅源关键字检索
- 组合筛选：时间范围（今天/本周/本月/自定义）+ 仅订阅 / 全天 / 有提醒
- 点击结果：自动跳转到对应日期视图，并定位到事件时间段（“跳转 + 定位”）

### 4) ICS 导入 / 导出 & 订阅同步

- ICS 导入：从本地 `.ics` 文件解析并写入数据库
- ICS 导出：本地事件导出为 `.ics`
- ICS 订阅同步：
  - 支持多个订阅源
  - Dio 超时与失败兜底
  - **ETag / Last-Modified 增量同步**，处理 `304 Not Modified`，减少重复流量与写入
  - 同源去重更新：按 VEVENT `UID` upsert（同 UID 更新不重复插入）

### 5) 同步日志（可观测性）

- 每次同步记录：success / not_modified / failed、HTTP 状态码、拉取条数、耗时、错误原因
- 订阅页可直接查看最近一次同步状态，进入日志页查看历史记录

### 6) 提醒系统（时区一致 & Android 14+ 兼容）

- 时区初始化（TimeZone），保证展示与提醒触发一致
- 兼容 Android 14+ 通知权限/精确闹钟能力判断与兜底
- 支持提前提醒、全天事件规则与异常场景兜底

---

## 🧱 技术栈

- Flutter / Dart
- Riverpod（状态管理）
- Drift(SQLite)（本地数据库/事务/索引/迁移）
- Dio（网络请求）
- ICS(iCalendar)（导入/导出/订阅）
- TimeZone + 本地通知（提醒调度）

---

## 🗂️ 项目结构（核心模块）

```
lib/
  core/
    db/
      app_db.dart                # Drift 表结构/查询/事务/迁移/索引
      db_provider.dart           # AppDb Provider（后台 isolate 打开 DB）
    lunar/
      lunar_utils.dart           # 农历工具
  features/
    calendar/
      presentation/
        calendar_page.dart       # 月/周/日三视图 + 交互 + Today
        calendar_state.dart      # tab / visibleDate providers
        calendar_search_page.dart# 搜索/筛选 + 跳转定位
    event/
      presentation/
        event_edit_page.dart     # 新建/编辑（全天/恢复时间/提醒）
      data/
        event_providers.dart     # eventsInRangeProvider（范围流/懒加载）
    ics/
      ics_import.dart            # ICS 导入
      ics_export.dart            # ICS 导出
    subscription/
      subscription_page.dart     # 订阅源管理 + 同步入口 + 日志入口
      subscription_sync_service.dart # 增量同步 + 批量写库 + 日志落库
      sync_logs_page.dart        # 同步日志页面
test/
  events_range_query_test.dart
  upsert_event_from_source_test.dart
  search_filter_test.dart
```

---

## 关键实现

### 1) 区间相交查询（跨日事件不丢）

周/日范围查询采用区间相交条件避免漏掉跨日事件：
`event.start < rangeEnd && event.end > rangeStart`

### 2) 搜索 → 跳转 → 定位

搜索结果点击后：

- 更新 `visibleDateProvider` 与 `calendarTabProvider` 联动切换视图/日期
- 根据 `startAt` 计算分钟数映射滚动 offset，实现定位到事件时间段

### 3) 订阅增量同步（ETag / Last-Modified）

- 请求携带 `If-None-Match` / `If-Modified-Since`
- 304 直接跳过解析写库
- 200 解析 ICS → 按 `UID` upsert → 事务/批量写入

### 4) 同步日志（Observability）

- `startSyncLog()` / `finishSyncLog()` 记录 status、耗时、条数、错误
- UI 可查看最近一次同步状态与历史日志，便于排障与展示

---

## 快速开始

### 环境要求

- Flutter SDK（稳定版）
- Android Studio + Emulator / 真机

### 运行

```bash
flutter pub get
flutter run
```

> 若提示 `No pubspec.yaml file found`，请确认命令在 Flutter 工程根目录执行（存在 `pubspec.yaml`）。

---

## 测试

```bash
flutter test
```

包含（示例）：

- 跨日事件范围查询（区间相交）
- 订阅 UID upsert 不重复插入
- 搜索筛选组合条件正确性

---

## 性能数据/压测（可复现）

项目内置“性能压测”入口（右上角菜单）：

- 一键生成/导入大量事件（如 5000）
- 打点输出：写入耗时、周范围查询耗时、（可选）搜索耗时
  用于复现实验数据与对比优化前后效果。

---

## Roadmap（可选）

- 订阅后台定时刷新（WorkManager/Alarm）
- 事件冲突检测与空闲建议
- 更完善的统计面板（热力图/时段分布）

---

## License

个人学习与作品展示用途。如需开源协议可改为 MIT/Apache-2.0。

---
