import 'package:flutter/services.dart';

/// Flutter 与原生（Kotlin）之间的桥接。
class Native {
  static const MethodChannel _m = MethodChannel('scheduled_tapper/control');
  static const EventChannel logs = EventChannel('scheduled_tapper/logs');
  static const EventChannel state = EventChannel('scheduled_tapper/state');
  static const EventChannel pick = EventChannel('scheduled_tapper/pick');

  static Future<Map<String, dynamic>> getState() async =>
      Map<String, dynamic>.from((await _m.invokeMethod('getState')) as Map);

  static Future<String> getConfig() async =>
      (await _m.invokeMethod('getConfig')) as String;

  static Future<void> saveConfig(String json) async =>
      _m.invokeMethod('saveConfig', {'json': json});

  static Future<void> startService() async => _m.invokeMethod('startService');
  static Future<void> showOverlay() async => _m.invokeMethod('showOverlay');
  static Future<void> hideOverlay() async => _m.invokeMethod('hideOverlay');
  static Future<void> enterPickMode() async => _m.invokeMethod('enterPickMode');
  static Future<void> togglePanel() async => _m.invokeMethod('togglePanel');
  static Future<void> openPicker() async => _m.invokeMethod('openPicker');
  static Future<void> closePanel() async => _m.invokeMethod('closePanel');
  static Future<void> cancelPickMode() async => _m.invokeMethod('cancelPickMode');
  static Future<void> openAccessibilitySettings() async =>
      _m.invokeMethod('openAccessibilitySettings');
  static Future<void> openOverlaySettings() async =>
      _m.invokeMethod('openOverlaySettings');
  static Future<void> clearLog() async => _m.invokeMethod('clearLog');
  static Future<String> getLogs() async => (await _m.invokeMethod('getLogs')) as String;
  static Future<void> abort() async => _m.invokeMethod('abort');

  static Future<bool> testTap(int x, int y) async =>
      (await _m.invokeMethod('testTap', {'x': x, 'y': y})) as bool;

  static Future<bool> runNow(String label, String json) async =>
      (await _m.invokeMethod('runNow', {'label': label, 'json': json})) as bool;

  /// 在屏幕上显示某个时间点所有步骤坐标的十字+圆框标记（开启该时间点开关时调用）。
  static Future<void> showPointMarkers(String json) async =>
      _m.invokeMethod('showPointMarkers', {'json': json});

  /// 移除屏幕上的坐标标记（关闭时间点开关，或全应用不显示任何已启用时间点时调用）。
  static Future<void> hidePointMarkers() async => _m.invokeMethod('hidePointMarkers');
}
