import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduled_tapper/main.dart';
import 'package:scheduled_tapper/models.dart';

/// 阶段 2/3 的可观测验证（Flutter 侧）：分组管理对话框、分组名同步、持久化写入。
///
/// 说明：主界面时间点已平铺展示，分组通过顶部「分组管理」对话框维护；
/// 悬浮窗内的分组列表由 Android 原生渲染，无法在 Flutter/JVM 测试环境渲染。
/// 因此这里验证：
///  1. 平铺卡片的分组名来自模型「同一数据源」（时间点卡片 subtitle）
///  2. 分组管理对话框可新建、可重命名，且确实写进发给原生的 JSON
///  3. 原生写入（改名）后主界面通过 configChanged 同步到同一份数据

const _methodChannel = MethodChannel('scheduled_tapper/control');
const _logsChannel = EventChannel('scheduled_tapper/logs');
const _stateChannel = EventChannel('scheduled_tapper/state');
const _pickChannel = EventChannel('scheduled_tapper/pick');

void _setPhoneSurface(WidgetTester tester, {double w = 360, double h = 900}) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

class _PickEvents {
  MockStreamHandlerEventSink? sink;
  void success(Object event) => sink!.success(event);
}

_PickEvents _mockNative(String Function() configJson, {List<String>? saved}) {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final events = _PickEvents();
  messenger.setMockMethodCallHandler(_methodChannel, (call) async {
    switch (call.method) {
      case 'getConfig':
        return configJson();
      case 'saveConfig':
        saved?.add((call.arguments as Map)['json'] as String);
        return true;
      case 'getState':
        return <String, dynamic>{
          'a11y': true, 'a11ySettings': true, 'overlay': true,
          'running': false, 'next': '-', 'tz': 'GMT+8',
        };
      case 'getLogs':
        return '';
      default:
        return true;
    }
  });
  for (final ch in [_logsChannel, _stateChannel]) {
    messenger.setMockStreamHandler(ch, MockStreamHandler.inline(onListen: (args, sink) {}));
  }
  messenger.setMockStreamHandler(_pickChannel, MockStreamHandler.inline(onListen: (args, sink) {
    events.sink = sink;
  }));
  return events;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('阶段2 · 主页面分组名', () {
    testWidgets('平铺卡片的分组名来自同一数据源（subtitle 显示）', (tester) async {
      _setPhoneSurface(tester);
      final cfg = TapperConfig(
        points: [
          TimePoint(hour: 8, minute: 0, second: 0, groupId: 'g1'),
          TimePoint(hour: 9, minute: 0, second: 0, groupId: 'g2'),
        ],
        groups: [PointGroup(id: 'g1', name: '早班'), PointGroup(id: 'g2', name: '晚班')],
      );
      _mockNative(() => cfg.toJsonString());
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      // 平铺展示：每个时间点卡片 subtitle 第一行显示其分组名
      expect(find.text('早班'), findsOneWidget, reason: '归属早班的卡片显示「早班」');
      expect(find.text('晚班'), findsOneWidget, reason: '归属晚班的卡片显示「晚班」');
    });

    testWidgets('分组管理：可新建分组并持久化到发给原生的 JSON', (tester) async {
      _setPhoneSurface(tester);
      final saved = <String>[];
      final cfg = TapperConfig(points: [TimePoint(hour: 8)]);
      _mockNative(() => cfg.toJsonString(), saved: saved);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      // 顶部分组管理入口
      await tester.tap(find.byTooltip('分组管理'));
      await tester.pumpAndSettle();

      // 对话框内「新建分组」（此时仅一处）
      await tester.tap(find.text('新建分组'));
      await tester.pumpAndSettle();
      // _promptText 弹窗与对话框按钮都含「新建分组」/「确定」，取最新弹层的按钮
      await tester.enterText(find.byType(TextField).last, '夜班');
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();
      expect(find.text('夜班'), findsOneWidget, reason: '对话框应立即列出新分组');

      // 确定分组管理（弹窗已关闭，此时唯一）
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(saved, isNotEmpty, reason: '应已保存');
      final o = jsonDecode(saved.last) as Map<String, dynamic>;
      final groups = (o['groups'] as List).cast<Map<String, dynamic>>();
      expect(groups.map((g) => g['name']), contains('夜班'), reason: '新分组应写入 JSON');
    });

    testWidgets('分组管理：重命名分组后主页面立即显示新名称', (tester) async {
      _setPhoneSurface(tester);
      final saved = <String>[];
      final cfg = TapperConfig(
        points: [TimePoint(hour: 8, groupId: 'g1')],
        groups: [PointGroup(id: 'g1', name: '早班')],
      );
      _mockNative(() => cfg.toJsonString(), saved: saved);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      expect(find.text('早班'), findsOneWidget);

      await tester.tap(find.byTooltip('分组管理'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('重命名').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '清晨班');
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();
      // 改名后对话框内出现新名（对话框为模态，主界面在下层仍渲染，故此处不校验旧名消失）
      expect(find.text('清晨班'), findsOneWidget, reason: '对话框应立即显示新名');

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('清晨班'), findsOneWidget, reason: '改名后卡片 subtitle 立即同步');
      expect(find.text('早班'), findsNothing, reason: '旧名称不应残留');

      final o = jsonDecode(saved.last) as Map<String, dynamic>;
      final groups = (o['groups'] as List).cast<Map<String, dynamic>>();
      final renamed = groups.firstWhere((g) => g['id'] == 'g1');
      expect(renamed['name'], '清晨班', reason: '新名称必须持久化');
    });

    testWidgets('分组管理：同一分组名不能重复创建（唯一性校验）', (tester) async {
      _setPhoneSurface(tester);
      final saved = <String>[];
      final cfg = TapperConfig(
        points: [TimePoint(hour: 8, groupId: 'g1')],
        groups: [PointGroup(id: 'g1', name: '早班')],
      );
      _mockNative(() => cfg.toJsonString(), saved: saved);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      // 忽略初始化保存，聚焦「重名提示后不应产生新提交」
      saved.clear();
      await tester.tap(find.byTooltip('分组管理'));
      await tester.pumpAndSettle();

      // 尝试新建同名分组：应被拒绝并提示
      await tester.tap(find.text('新建分组'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '早班');
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('已存在'), findsOneWidget, reason: '重名应给出提示');
      expect(saved, isEmpty, reason: '未提交前不应保存');
    });
  });

  group('阶段3 · 原生改分组后主界面同步（同一数据源）', () {
    testWidgets('收到 configChanged 后重新读取分组与名称', (tester) async {
      _setPhoneSurface(tester);
      var json = TapperConfig(
        points: [TimePoint(hour: 8, groupId: 'g1')],
        groups: [PointGroup(id: 'g1', name: '早班')],
      ).toJsonString();
      final pick = _mockNative(() => json);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      expect(find.text('早班'), findsOneWidget);

      // 模拟：悬浮窗侧改名并写回同一份配置，然后广播 configChanged
      json = TapperConfig(
        points: [TimePoint(hour: 8, groupId: 'g1')],
        groups: [PointGroup(id: 'g1', name: '悬浮窗改的名')],
      ).toJsonString();
      pick.success(<String, dynamic>{'configChanged': true});
      await tester.pumpAndSettle();

      expect(find.text('悬浮窗改的名'), findsOneWidget, reason: '主界面应与原生同一份数据');
      expect(find.text('早班'), findsNothing);
    });
  });
}