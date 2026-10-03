import 'package:flutter_test/flutter_test.dart';
import 'package:scheduled_tapper/models.dart';

/// 第 3 项（时/分/秒 集合字段）的模型验证。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('第3项 · 时间点标签（展示全部信息）', () {
    test('单选：与旧格式信息量一致', () {
      expect(TimePoint(hour: 8, minute: 30, second: 15).label, '08时 30分 15秒');
    });

    test('多选：逗号分隔', () {
      final p = TimePoint(hour: 8, minute: 30, second: 0,
          hours: [8, 12], minutes: [30], seconds: [0]);
      expect(p.label, '08,12时 30分 00秒');
    });

    test('连续值压缩成区间', () {
      // 「每小时」用 hour:-1（既有语义），集合为空
      final p = TimePoint(hour: -1, minute: 0, second: 3,
          minutes: List.generate(11, (i) => i), seconds: [3]);
      expect(p.label, '每小时 00-10分 03秒');
    });

    test('全选小时显示「全部小时」，与「每小时」区分', () {
      final all = TimePoint(hour: 0, minute: 30, second: 0,
          hours: List.generate(24, (i) => i), minutes: [30], seconds: [0]);
      expect(all.label, '全部小时 30分 00秒');
      final hourly = TimePoint(hour: -1, minute: 30, second: 0);
      expect(hourly.label, '每小时 30分 00秒');
    });

    test('多字段同时多选时全部展示，不截断', () {
      final p = TimePoint(hour: 8, minute: 0, second: 0,
          hours: [8, 12], minutes: [0, 30], seconds: [0, 15]);
      expect(p.label, '08,12时 00,30分 00,15秒');
    });
  });

  group('第3项 · 组合展开与上限', () {
    test('单选 = 1 个时刻；多选 = 笛卡尔积', () {
      expect(TimePoint(hour: 8, minute: 30, second: 0).combos.length, 1);
      final p = TimePoint(hour: 8, minute: 30, second: 0,
          hours: [8, 12], minutes: [10, 20], seconds: [0, 30]);
      expect(p.combos.length, 8);
    });

    test('超过上限时标记为超限（24×60×60）', () {
      final p = TimePoint(hour: 0, minute: 0, second: 0,
          hours: List.generate(24, (i) => i),
          minutes: List.generate(60, (i) => i),
          seconds: List.generate(60, (i) => i));
      expect(p.comboCount, 86400);
      expect(p.exceedsComboLimit, isTrue);
    });

    test('集合为空时回落到单值字段（旧数据兼容）', () {
      final p = TimePoint(hour: 8, minute: 30, second: 15);
      expect(p.effectiveHours, [8]);
      expect(p.effectiveMinutes, [30]);
      expect(p.effectiveSeconds, [15]);
      final h = TimePoint(hour: -1, minute: 5, second: 3);
      expect(h.effectiveHours, isEmpty);
    });
  });

  group('第3项 · 集合持久化', () {
    test('集合写入 JSON 并可往返', () {
      final p = TimePoint(hour: 8, minute: 0, second: 0,
          hours: [8, 12], minutes: [0, 30], seconds: [0]);
      final back = TimePoint.fromJson(p.toJson());
      expect(back.hours, [8, 12]);
      expect(back.minutes, [0, 30]);
      expect(back.seconds, [0]);
      expect(back.label, '08,12时 00,30分 00秒');
    });

    test('集合为空时不写入这些键（保持旧 JSON 形态）', () {
      final o = TimePoint(hour: 8, minute: 0, second: 0).toJson();
      expect(o.containsKey('hours'), isFalse);
      expect(o.containsKey('minutes'), isFalse);
      expect(o.containsKey('seconds'), isFalse);
    });
  });
}
