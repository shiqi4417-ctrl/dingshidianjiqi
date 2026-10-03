import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scheduled_tapper/models.dart';

/// 阶段 2（时间点分组）的可观测验证：模型层。
///
/// 覆盖：创建/重命名、持久化往返、旧数据兼容、删除分组的连带语义。
/// 注意：主界面时间点已平铺展示；模型层不再强制存在默认组（可按需自建分组）。
void main() {
  group('阶段2 · 分组模型', () {
    test('新配置默认不附带任何分组', () {
      final cfg = TapperConfig();
      expect(cfg.groups, isEmpty);
    });

    test('无分组时，时间点不归属任何组（grouped 结果为空）', () {
      final cfg = TapperConfig(points: [TimePoint(hour: 8), TimePoint(hour: 9)]);
      final grouped = cfg.grouped();
      expect(grouped, isEmpty, reason: '没有分组时不产生孤儿归属');
    });

    test('可创建分组并把时间点归类', () {
      final a = PointGroup(name: '早班');
      final b = PointGroup(name: '晚班');
      final p1 = TimePoint(hour: 8, groupId: a.id);
      final p2 = TimePoint(hour: 20, groupId: b.id);
      final p3 = TimePoint(hour: 12, groupId: a.id);
      final cfg = TapperConfig(points: [p1, p2, p3], groups: [a, b]);

      final grouped = cfg.grouped();
      expect(grouped.length, 2, reason: '早班 + 晚班');
      expect(grouped[0].key.name, '早班');
      expect(grouped[0].value.length, 2);
      expect(grouped[1].key.name, '晚班');
      expect(grouped[1].value.single.id, p2.id);
    });

    test('重命名分组后，所有引用处读到的是同一个新名称', () {
      final g = PointGroup(name: '早班');
      final cfg = TapperConfig(points: [TimePoint(hour: 8, groupId: g.id)], groups: [g]);
      g.name = '清晨班';
      // grouped() 每次实时读取 groups，因此主页面/悬浮窗/选择器（同一数据源）都会看到新名字
      expect(cfg.grouped()[0].key.name, '清晨班');
      expect(cfg.groupById(g.id)!.name, '清晨班');
    });

    test('允许空分组（存在但没有成员）', () {
      final empty = PointGroup(name: '空组');
      final busy = PointGroup(name: '有成员组');
      // 把点明确归到 busy 组，让 empty 组保持空
      final cfg = TapperConfig(
          points: [TimePoint(hour: 8, groupId: busy.id)], groups: [empty, busy]);
      final grouped = cfg.grouped();
      final e = grouped.firstWhere((x) => x.key.id == empty.id);
      expect(e.value, isEmpty);
    });

    test('删除分组会连同组内时间点一起删除（模型层语义）', () {
      final g = PointGroup(name: '早班');
      final keepGroup = PointGroup(name: '保留组');
      final keep = TimePoint(hour: 9, groupId: keepGroup.id);
      final cfg = TapperConfig(
          points: [TimePoint(hour: 8, groupId: g.id), keep],
          groups: [g, keepGroup]);
      // 与 main.dart 删除分组相同的操作
      cfg.points.removeWhere((p) => p.groupId == g.id);
      cfg.groups.removeWhere((x) => x.id == g.id);
      expect(cfg.points.length, 1);
      expect(cfg.points.single.id, keep.id);
      expect(cfg.groups.length, 1);
    });

    test('指向不存在分组的时间点回落到第一个分组（不产生孤儿）', () {
      final g = PointGroup(name: '早班');
      final cfg = TapperConfig(
          points: [TimePoint(hour: 8, groupId: '已删除的组')], groups: [g]);
      cfg.normalizePointGroups();
      expect(cfg.points.single.groupId, g.id);
      expect(cfg.grouped().first.value.length, 1);
    });

    test('分组成员删除后，多余分组不自动删除（由主界面删除逻辑负责）', () {
      final g = PointGroup(name: '早班');
      final cfg = TapperConfig(points: [TimePoint(hour: 8, groupId: g.id)], groups: [g]);
      cfg.points.removeWhere((p) => p.groupId == g.id);
      expect(cfg.groups.length, 1, reason: '模型层不自动删空组，isDefaultGroup 判断在 UI 逻辑');
    });

    test('默认组标记：isDefaultGroup 仅对 defaultGroupId 成立', () {
      final cfg = TapperConfig();
      expect(cfg.isDefaultGroup(TapperConfig.defaultGroupId), isTrue);
      expect(cfg.isDefaultGroup('早班'), isFalse);
    });
  });

  group('阶段2 · 持久化往返（刷新/重进不丢失）', () {
    test('分组、名称与时间点归属经 JSON 往返后保持不变', () {
      final g = PointGroup(name: '早班');
      final cfg = TapperConfig(
        points: [TimePoint(hour: 8, groupId: g.id), TimePoint(hour: 9, groupId: g.id)],
        groups: [g],
      );
      final restored = TapperConfig.fromJsonString(cfg.toJsonString());

      expect(restored.groups.length, 1);
      expect(restored.groups[0].name, '早班');
      expect(restored.groups[0].id, g.id);
      expect(restored.points[0].groupId, g.id, reason: '时间点归属必须持久化');
      expect(restored.points[1].groupId, g.id);
    });

    test('JSON 里确实写入了 groups 与 groupId 字段', () {
      final g = PointGroup(name: '早班');
      final cfg = TapperConfig(points: [TimePoint(hour: 8, groupId: g.id)], groups: [g]);
      final o = jsonDecode(cfg.toJsonString()) as Map<String, dynamic>;
      expect(o['groups'], isA<List>());
      expect((o['groups'] as List).length, 1);
      expect((o['points'] as List).first['groupId'], g.id);
    });

    test('旧数据（没有 groups/groupId）读取不报错，分组为空', () {
      const legacy = '{"version":1,"tapDurationMs":30,"points":['
          '{"id":"p1","hour":8,"minute":0,"second":0,"enabled":true,'
          '"repeatCount":1,"repeatIntervalMs":0,"steps":[]}]}';
      final cfg = TapperConfig.fromJsonString(legacy);
      expect(cfg.points.single.id, 'p1');
      // 兼容旧数据：旧 JSON 无 groups -> 当前按"无分组"处理，不强行制造默认组
      expect(cfg.groups, isEmpty);
    });

    test('损坏的 JSON 不抛异常', () {
      expect(TapperConfig.fromJsonString('{不是json').points, isEmpty);
      expect(TapperConfig.fromJsonString('{不是json').groups, isEmpty);
    });
  });

  group('阶段2 · 跨语言键名一致（防止 Kotlin 端丢弃分组）', () {
    test('TimePoint JSON 包含 groupId', () {
      final o = TimePoint(hour: 8, groupId: 'g1').toJson();
      expect(o['groupId'], 'g1');
    });

    test('PointGroup JSON 键名为 id/name', () {
      final o = PointGroup(id: 'g1', name: '早班').toJson();
      expect(o.keys.toSet(), {'id', 'name'});
    });
  });
}