import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduled_tapper/main.dart';
import 'package:scheduled_tapper/models.dart';

/// 长按菜单 + 复制 + 默认值的可观测验证（匹配当前平铺 UI）。
///
/// 覆盖：
///  1. 长按时间点弹出菜单，含修改/上移/下移/复制/删除 五项
///  2. 复制后出现一条内容一致的新时间点（enabled 按确认强制关闭）
///  3. 时间点卡片默认收起；展开后步骤行/执行入口才可见
///  4. 分组管理与删除分组语义在模型层覆盖

const _methodChannel = MethodChannel('scheduled_tapper/control');
const _logsChannel = EventChannel('scheduled_tapper/logs');
const _stateChannel = EventChannel('scheduled_tapper/state');
const _pickChannel = EventChannel('scheduled_tapper/pick');

void _setPhoneSurface(WidgetTester tester, {double w = 360, double h = 900}) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void _mockNative(String Function() configJson, {List<String>? saved, List<String>? calls, bool a11y = true}) {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_methodChannel, (call) async {
    calls?.add(call.method);
    switch (call.method) {
      case 'getConfig':
        return configJson();
      case 'saveConfig':
        saved?.add((call.arguments as Map)['json'] as String);
        return true;
      case 'getState':
        return <String, dynamic>{
          'a11y': a11y, 'a11ySettings': true, 'overlay': true,
          'running': false, 'next': '-', 'tz': 'GMT+8',
        };
      case 'getLogs':
        return '';
      default:
        return true;
    }
  });
  for (final ch in [_logsChannel, _stateChannel, _pickChannel]) {
    messenger.setMockStreamHandler(ch, MockStreamHandler.inline(onListen: (args, sink) {}));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('阶段2 · 长按菜单', () {
    testWidgets('长按时间点弹出五项菜单', (tester) async {
      _setPhoneSurface(tester);
      final cfg = TapperConfig(points: [
        TimePoint(hour: 8, minute: 5, second: 30),
        TimePoint(hour: 9, minute: 0, second: 0),
      ]);
      _mockNative(() => cfg.toJsonString());
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      // 未长按时菜单不存在
      expect(find.text('复制'), findsNothing);

      await tester.longPress(find.text('08时 05分 30秒'));
      await tester.pumpAndSettle();

      // 当前平铺 UI 的菜单为五项（无「分组」项）
      for (final item in ['修改', '上移', '下移', '复制', '删除']) {
        expect(find.text(item), findsOneWidget, reason: '长按菜单应含「' + item + '」');
      }
    });

    testWidgets('卡片默认收起：展开后才有步骤行与执行按钮', (tester) async {
      _setPhoneSurface(tester);
      final cfg = TapperConfig(points: [
        TimePoint(hour: 8, minute: 0, second: 0, steps: [
          TapStep(x: 540, y: 1200, delayMs: 300, sw: 1080, sh: 2400),
        ]),
      ]);
      _mockNative(() => cfg.toJsonString());
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      // 默认收起：时间点标题可见，但步骤/执行入口不可见
      expect(find.text('08时 00分 00秒'), findsOneWidget);
      expect(find.textContaining('到下一步延时'), findsNothing, reason: '步骤行不应直接可见');
      expect(find.text('立即执行一次'), findsNothing, reason: '执行按钮不应直接可见');

      // 展开后可见
      await tester.tap(find.text('08时 00分 00秒'));
      await tester.pumpAndSettle();
      expect(find.textContaining('到下一步延时'), findsOneWidget);
      expect(find.text('立即执行一次'), findsOneWidget);
    });

    testWidgets('首项的上移、末项的下移在菜单中禁用', (tester) async {
      _setPhoneSurface(tester);
      final cfg = TapperConfig(points: [
        TimePoint(hour: 8, minute: 0, second: 0),
        TimePoint(hour: 9, minute: 0, second: 0),
      ]);
      _mockNative(() => cfg.toJsonString());
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('08时 00分 00秒'));
      await tester.pumpAndSettle();
      var up = tester.widget<PopupMenuItem<String>>(
          find.widgetWithText(PopupMenuItem<String>, '上移'));
      var down = tester.widget<PopupMenuItem<String>>(
          find.widgetWithText(PopupMenuItem<String>, '下移'));
      expect(up.enabled, isFalse, reason: '首项上移应禁用');
      expect(down.enabled, isTrue);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('09时 00分 00秒'));
      await tester.pumpAndSettle();
      up = tester.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, '上移'));
      down = tester.widget<PopupMenuItem<String>>(
          find.widgetWithText(PopupMenuItem<String>, '下移'));
      expect(up.enabled, isTrue);
      expect(down.enabled, isFalse, reason: '末项下移应禁用');
    });

    testWidgets('菜单「上移」沿用原有交换逻辑', (tester) async {
      _setPhoneSurface(tester);
      final saved = <String>[];
      final cfg = TapperConfig(points: [
        TimePoint(hour: 8, minute: 0, second: 0),
        TimePoint(hour: 9, minute: 0, second: 0),
      ]);
      _mockNative(() => cfg.toJsonString(), saved: saved);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('09时 00分 00秒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上移'));
      await tester.pumpAndSettle();

      final o = jsonDecode(saved.last) as Map<String, dynamic>;
      final pts = (o['points'] as List).cast<Map<String, dynamic>>();
      expect(pts[0]['hour'], 9, reason: '上移后 9 点应在最前');
      expect(pts[1]['hour'], 8);
    });

    testWidgets('菜单「删除」沿用原有删除逻辑', (tester) async {
      _setPhoneSurface(tester);
      final saved = <String>[];
      final cfg = TapperConfig(points: [
        TimePoint(hour: 8, minute: 0, second: 0),
        TimePoint(hour: 9, minute: 0, second: 0),
      ]);
      _mockNative(() => cfg.toJsonString(), saved: saved);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('08时 00分 00秒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      final o = jsonDecode(saved.last) as Map<String, dynamic>;
      final pts = (o['points'] as List).cast<Map<String, dynamic>>();
      expect(pts.length, 1);
      expect(pts[0]['hour'], 9, reason: '8 点应被删除');
    });

    testWidgets('删除时间点后，所在分组若变空则自动删除该空分组', (tester) async {
      _setPhoneSurface(tester);
      final saved = <String>[];
      final cfg = TapperConfig(
        points: [TimePoint(hour: 8, minute: 0, second: 0, groupId: 'g1')],
        groups: [PointGroup(id: 'g1', name: '早班')],
      );
      _mockNative(() => cfg.toJsonString(), saved: saved);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('08时 00分 00秒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      final o = jsonDecode(saved.last) as Map<String, dynamic>;
      expect(o['points'] as List, isEmpty, reason: '时间点被删除');
      expect(o['groups'] as List, isEmpty,
          reason: '删除后该分组无成员，应自动删除空分组（默认组除外）');
    });

    testWidgets('开启时间点开关时若无无障碍权限则拒绝并提示', (tester) async {
      _setPhoneSurface(tester);
      final calls = <String>[];
      _mockNative(() => TapperConfig(points: [
            TimePoint(hour: 8, minute: 0, second: 0),
          ]).toJsonString(), calls: calls, a11y: false);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      final sw = find.byType(Switch).first;
      expect(tester.widget<Switch>(sw).value, isFalse, reason: '初始为关闭');
      await tester.tap(sw);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(sw).value, isFalse, reason: '无权限时不应打开');
      expect(find.textContaining('无障碍权限'), findsOneWidget, reason: '应提示先开无障碍');
      expect(calls, contains('openAccessibilitySettings'), reason: '应跳转无障碍设置');
    });
  });

  group('阶段3 · 复制', () {
    testWidgets('复制后同分组出现内容一致的新时间点', (tester) async {
      _setPhoneSurface(tester);
      final saved = <String>[];
      final cfg = TapperConfig(
        points: [
          TimePoint(
            hour: 8, minute: 5, second: 30,
            enabled: true,
            repeatCount: 4,
            repeatIntervalMs: 500,
            groupId: 'g1',
            steps: [TapStep(x: 540, y: 1200, delayMs: 300, sw: 1080, sh: 2400)],
          ),
        ],
        groups: [PointGroup(id: 'g1', name: '早班')],
      );
      _mockNative(() => cfg.toJsonString(), saved: saved);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('08时 05分 30秒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      final o = jsonDecode(saved.last) as Map<String, dynamic>;
      final pts = (o['points'] as List).cast<Map<String, dynamic>>();
      expect(pts.length, 2, reason: '应新增一条');

      final orig = pts[0];
      final copy = pts[1];
      expect(copy['hour'], orig['hour']);
      expect(copy['minute'], orig['minute']);
      expect(copy['second'], orig['second']);
      expect(copy['repeatCount'], orig['repeatCount']);
      expect(copy['repeatIntervalMs'], orig['repeatIntervalMs']);
      expect(copy['groupId'], 'g1', reason: '不跨分组，应与原项同组');
      expect(copy['enabled'], isFalse, reason: '按确认：复制项默认关闭');
      expect(orig['enabled'], isTrue, reason: '原项不应被改动');
      expect((copy['steps'] as List).length, 1, reason: '步骤应一并复制');
      expect((copy['steps'] as List).first['x'], 540);
      expect((copy['steps'] as List).first['delayMs'], 300);
      expect(copy['id'], isNot(orig['id']), reason: '新项 id 应不同');
    });

    testWidgets('复制项插入在原项之后（线性表内紧邻）', (tester) async {
      _setPhoneSurface(tester);
      final saved = <String>[];
      final cfg = TapperConfig(points: [
        TimePoint(hour: 8, minute: 0, second: 0),
        TimePoint(hour: 9, minute: 0, second: 0),
        TimePoint(hour: 10, minute: 0, second: 0),
      ]);
      _mockNative(() => cfg.toJsonString(), saved: saved);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('09时 00分 00秒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      final o = jsonDecode(saved.last) as Map<String, dynamic>;
      final pts = (o['points'] as List).cast<Map<String, dynamic>>();
      expect(pts.length, 4);
      expect(pts[0]['hour'], 8);
      expect(pts[1]['hour'], 9, reason: '原项仍在第 2 位');
      expect(pts[2]['hour'], 9, reason: '复制项紧跟在原项之后');
      expect(pts[3]['hour'], 10);
    });
  });

  group('阶段4 · 默认值', () {
    testWidgets('模型层：TimePoint 默认 enabled=false，但旧数据缺字段仍回落 true', (tester) async {
      expect(TimePoint(hour: 8).enabled, isFalse, reason: '新建默认关闭');
      final legacy = TimePoint.fromJson(<String, dynamic>{'id': 'x', 'hour': 8});
      expect(legacy.enabled, isTrue, reason: '旧数据缺 enabled 字段时应回落为 true（既有兼容行为）');
    });
  });
}