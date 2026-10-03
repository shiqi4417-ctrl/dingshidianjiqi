import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduled_tapper/main.dart';
import 'package:scheduled_tapper/models.dart';

/// 悬浮窗「取点」的接入验证（Flutter 侧）。
///
/// Android 的 WindowManager 悬浮窗本身无法在 Flutter/JVM 测试环境渲染（已如实说明），
/// 因此这里验证的是**接入点与联动链路**：
///  1. 步骤行菜单提供「重新取点」入口，点击后确实请求原生进入取点模式
///  2. 未授权悬浮窗时不进入取点，而是提示并跳转系统设置
///  3. 原生写入配置后通过 configChanged 事件让主界面刷新（界面与持久化不脱节）
///  4. 取消取点后迟到的坐标事件不会误写入旧时间点（取消不产生写入）

const _methodChannel = MethodChannel('scheduled_tapper/control');
const _logsChannel = EventChannel('scheduled_tapper/logs');
const _stateChannel = EventChannel('scheduled_tapper/state');
const _pickChannel = EventChannel('scheduled_tapper/pick');

void _setPhoneSurface(WidgetTester tester, {double w = 360, double h = 800}) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// pick 事件流的推送句柄：原生事件只能在 HomePage 订阅之后推送，
/// 因此用可变持有者，而不是在订阅前就读取 sink。
class _PickEvents {
  MockStreamHandlerEventSink? sink;
  void success(Object event) {
    final s = sink;
    if (s == null) throw StateError('HomePage 尚未订阅 pick 事件流');
    s.success(event);
  }
}

_PickEvents _mockNative(
  String Function() configJson, {
  List<String>? calls,
  List<String>? saved,
  bool overlay = true,
}) {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final events = _PickEvents();
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
          'a11y': true,
          'a11ySettings': true,
          'overlay': overlay,
          'running': false,
          'next': '-',
          'tz': 'GMT+8',
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
  messenger.setMockStreamHandler(
    _pickChannel,
    MockStreamHandler.inline(onListen: (args, sink) {
      events.sink = sink;
    }),
  );
  return events;
}

String _cfgJson(List<TimePoint> points) => TapperConfig(points: points).toJsonString();

/// 展开第一个时间点卡片（平铺展示，卡片默认收起）。
Future<void> _expandFirstCard(WidgetTester tester) async {
  await tester.tap(find.text('08时 05分 30秒'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('悬浮窗取点 · 唤起入口', () {
    testWidgets('步骤行菜单提供「重新取点」，点击后请求原生进入取点模式', (tester) async {
      _setPhoneSurface(tester);
      final calls = <String>[];
      _mockNative(
        () => _cfgJson([
          TimePoint(hour: 8, minute: 5, second: 30, steps: [
            TapStep(x: 100, y: 200, delayMs: 200, sw: 1080, sh: 2400),
          ]),
        ]),
        calls: calls,
      );

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      await _expandFirstCard(tester);

      // 展开后能看到步骤行；打开步骤操作菜单 -> 重新取点
      await tester.tap(find.byTooltip('步骤操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新取点'));
      await tester.pumpAndSettle();

      expect(calls, contains('enterPickMode'), reason: '应请求原生进入取点模式');
    });

    testWidgets('未授权悬浮窗：提示并跳转设置，不进入取点模式', (tester) async {
      _setPhoneSurface(tester);
      final calls = <String>[];
      _mockNative(
        () => _cfgJson([
          TimePoint(hour: 8, minute: 5, second: 30, steps: [
            TapStep(x: 100, y: 200, delayMs: 200, sw: 1080, sh: 2400),
          ]),
        ]),
        calls: calls,
        overlay: false,
      );

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      await _expandFirstCard(tester);

      await tester.tap(find.byTooltip('步骤操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新取点'));
      await tester.pumpAndSettle();

      expect(find.textContaining('显示在其他应用上层'), findsOneWidget, reason: '应给出授权提示');
      expect(calls, contains('openOverlaySettings'), reason: '应跳转悬浮窗授权设置');
      expect(calls, isNot(contains('enterPickMode')), reason: '未授权时不应进入取点模式');
    });
  });

  group('悬浮窗取点 · 写入后主界面同步', () {
    testWidgets('收到 configChanged 事件后重新读取配置并刷新界面', (tester) async {
      _setPhoneSurface(tester);
      var json = _cfgJson([
        TimePoint(hour: 8, minute: 5, second: 30, steps: [
          TapStep(x: 540, y: 1200, delayMs: 200, sw: 1080, sh: 2400),
        ]),
      ]);
      final pick = _mockNative(() => json);

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      await _expandFirstCard(tester);
      expect(find.textContaining('1 步'), findsOneWidget, reason: '初始应有 1 步的时间点');

      // 模拟：悬浮窗内确认导入 -> 原生写入 Prefs 并广播 configChanged
      json = _cfgJson([
        TimePoint(hour: 8, minute: 5, second: 30, steps: [
          TapStep(x: 540, y: 1200, delayMs: 200, sw: 1080, sh: 2400),
          TapStep(x: 10, y: 20, delayMs: 150, sw: 1080, sh: 2400),
        ]),
      ]);
      pick.success(<String, dynamic>{'configChanged': true});
      await tester.pumpAndSettle();

      expect(find.textContaining('2 步'), findsOneWidget, reason: '主界面应刷新为原生写入后的最新配置');
    });
  });

  group('取点取消不产生写入', () {
    testWidgets('取消取点后迟到的坐标事件不会误写入旧时间点', (tester) async {
      _setPhoneSurface(tester);
      final saved = <String>[];
      final pick = _mockNative(
        () => _cfgJson([
          TimePoint(hour: 8, minute: 5, second: 30, steps: [
            TapStep(x: 100, y: 200, delayMs: 200, sw: 1080, sh: 2400),
          ]),
        ]),
        saved: saved,
      );

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      await _expandFirstCard(tester);

      // 进入取点模式前的初始化保存忽略，聚焦「取消取点之后是否有新写入」
      saved.clear();
      await tester.tap(find.byTooltip('步骤操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新取点'));
      await tester.pumpAndSettle();

      pick.success(<String, dynamic>{'active': true});
      await tester.pumpAndSettle();
      // 用户取消取点
      pick.success(<String, dynamic>{'active': false});
      await tester.pumpAndSettle();
      // 迟到的坐标事件（例如取消瞬间已派发）
      pick.success(<String, dynamic>{'x': 10, 'y': 20, 'sw': 1080, 'sh': 2400});
      await tester.pumpAndSettle();

      expect(saved, isEmpty, reason: '取消取点后不应向原生写入任何配置');
      expect(find.textContaining('1 步'), findsOneWidget, reason: '时间点步数应保持不变');
    });
  });
}