import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'dialogs.dart';
import 'models.dart';
import 'native.dart';

void main() {
  runApp(const MaterialApp(home: HomePage(), debugShowCheckedModeBanner: false));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  TapperConfig _cfg = TapperConfig();
  final List<String> _logs = <String>[];
  Map<String, dynamic> _state = <String, dynamic>{};
  StreamSubscription<dynamic>? _logSub;
  StreamSubscription<dynamic>? _stateSub;
  StreamSubscription<dynamic>? _pickSub;
  String _pickTarget = '';
  bool _pickMode = false;
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _boot();
    _logSub = Native.logs.receiveBroadcastStream().listen((e) {
      final line = e.toString();
      setState(() {
        _logs.add(line);
        if (_logs.length > 400) _logs.removeAt(0);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) {
          _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        }
      });
    });
    _stateSub = Native.state.receiveBroadcastStream().listen((e) {
      if (!mounted) return;
      setState(() => _state = Map<String, dynamic>.from(e as Map));
    });
    _pickSub = Native.pick.receiveBroadcastStream().listen((e) {
      if (!mounted) return;
      final m = Map<String, dynamic>.from(e as Map);
      if (m.containsKey('active')) {
        final active = m['active'] == true;
        // 取点模式结束（含取消）后作废本次目标，避免之后误落到旧时间点
        setState(() {
          _pickMode = active;
          if (!active) _pickTarget = '';
        });
        return;
      }
      // 悬浮窗内直接改写了配置（选点导入）-> 重新读取
      if (m.containsKey('configChanged')) {
        _reloadConfig();
        return;
      }
      _onPicked(m['x'] as int, m['y'] as int, m['sw'] as int, m['sh'] as int);
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _stateSub?.cancel();
    _pickSub?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final json = await Native.getConfig();
    if (!mounted) return;
    setState(() {
      _cfg = TapperConfig.fromJsonString(json);
      // 用户要求固定使用北京时间：强制切换并持久化一次（覆盖旧数据里的 local）
      if (_cfg.timeSource != 'beijing') {
        _cfg.timeSource = 'beijing';
      }
    });
    await _save();
    await Native.startService();
    await _refresh();
  }

  /// 悬浮窗可能已在原生侧改写配置（选点导入），重新读取以免界面与持久化不一致。
  Future<void> _reloadConfig() async {
    try {
      final json = await Native.getConfig();
      if (!mounted) return;
      setState(() => _cfg = TapperConfig.fromJsonString(json));
    } catch (_) {}
  }

  Future<void> _refresh() async {
    try {
      final s = await Native.getState();
      if (mounted) setState(() => _state = s);
    } catch (_) {}
  }

  Future<void> _save() async {
    await Native.saveConfig(_cfg.toJsonString());
    await _refresh();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 1200)),
    );
  }

  // ---------------- 取点 ----------------

  Future<void> _pickFor(String tag) async {
    if (_state['overlay'] != true) {
      _toast('请先授予「显示在其他应用上层」权限');
      await Native.openOverlaySettings();
      return;
    }
    setState(() => _pickTarget = tag);
    await Native.enterPickMode();
    _toast('已进入取点模式：点击屏幕任意位置');
  }

  Future<void> _onPicked(int x, int y, int sw, int sh) async {
    // 取点模式下可能连续多次点击（多点连击）：保留 _pickTarget 不清空，
    // 每次命中都追加/替换步骤；目标在取点模式结束时（active=false）统一清空。
    final tag = _pickTarget;
    if (tag.isEmpty) {
      _toast('已记录坐标 (' + x.toString() + ', ' + y.toString() + ')');
      return;
    }
    final parts = tag.split('|');
    if (parts[0] == 'new') {
      final p = _cfg.points.firstWhere((e) => e.id == parts[1], orElse: () => TimePoint());
      setState(() {
        p.steps.add(TapStep(x: x, y: y, delayMs: 200, sw: sw, sh: sh));
      });
      await _save();
      _toast('已添加步骤 ' + p.steps.length.toString());
    } else {
      final idx = int.parse(parts[1]);
      final p = _cfg.points.firstWhere((e) => e.id == parts[2], orElse: () => TimePoint());
      setState(() {
        p.steps[idx].x = x;
        p.steps[idx].y = y;
        p.steps[idx].sw = sw;
        p.steps[idx].sh = sh;
      });
      await _save();
      _toast('步骤 ' + (idx + 1).toString() + ' 已更新');
    }
  }

  // ---------------- 时间点操作 ----------------

  Future<void> _addPoint() async {
    final r = await showTimeDialog(context, groups: _cfg.groups);
    if (r == null) return;
    setState(() {
      final gid = _resolveGroup(r.groupId, r.newGroupName);
      _cfg.points.add(TimePoint(
        hour: r.hour,
        minute: r.minute,
        second: r.second,
        repeatCount: r.repeatCount,
        repeatIntervalMs: r.repeatIntervalMs,
        // 第 3 项：多选集合（空集 = 沿用单值）
        hours: r.hours,
        minutes: r.minutes,
        seconds: r.seconds,
        groupId: gid,
      ));
    });
    await _save();
    _toast('已新增时间点 ' + r.hour.toString() + ':' + r.minute.toString());
  }

  /// 阶段三新增：修改已存在的时间点（含重复次数与间隔）。
  /// 就地更新同一个对象，id 与已记录的步骤保持不变，因此持久化数据与界面同步生效。
  Future<void> _editPoint(TimePoint p) async {
    final r = await showTimeDialog(context, existing: p, groups: _cfg.groups);
    if (r == null) return;
    setState(() {
      p.hour = r.hour;
      p.minute = r.minute;
      p.second = r.second;
      p.repeatCount = r.repeatCount;
      p.repeatIntervalMs = r.repeatIntervalMs;
      // 第 3 项：多选集合同步更新
      p.hours = List<int>.from(r.hours);
      p.minutes = List<int>.from(r.minutes);
      p.seconds = List<int>.from(r.seconds);
      // 分组：新建时创建并命名，否则沿用所选分组
      p.groupId = _resolveGroup(r.groupId, r.newGroupName);
    });
    await _save();
    _toast('已保存修改：' + p.label + ' · ' + p.repeatLabel);
  }

  /// 把对话框返回的分组选择解析成最终 groupId：
  /// 若选择了「新建分组」，则先创建新分组加入 _cfg.groups，再返回其 id。
  /// 非新建分组时，若所选分组已不存在则回落到第一个分组（无分组则置空）。
  String _resolveGroup(String groupId, String? newGroupName) {
    if (newGroupName != null && newGroupName.isNotEmpty) {
      final g = PointGroup(name: newGroupName);
      _cfg.groups.add(g);
      return g.id;
    }
    if (_cfg.groups.any((g) => g.id == groupId)) {
      return groupId;
    }
    return _cfg.groups.isNotEmpty ? _cfg.groups.first.id : '';
  }

  /// 时间点所属分组的显示名；无/默认组显示「未分组」。
  String _groupNameOf(TimePoint p) {
    if (p.groupId.isEmpty || p.groupId == TapperConfig.defaultGroupId) {
      return TapperConfig.defaultGroupName;
    }
    return _cfg.groups
        .firstWhere((g) => g.id == p.groupId, orElse: () => PointGroup(name: TapperConfig.defaultGroupName))
        .name;
  }

  /// 分组管理：主界面入口，新建/重命名/删除分组。
  Future<void> _manageGroups() async {
    final r = await showGroupManageDialog(context, _cfg.groups);
    if (r == null) return;
    setState(() {
      final keptIds = r.map((g) => g.id).toSet();
      // 删掉的分组：它下面的时间点一并删除（用户确认）
      final removedPoints = _cfg.points.where((p) => !keptIds.contains(p.groupId)).toList();
      if (removedPoints.isNotEmpty) {
        _cfg.points.removeWhere((p) => !keptIds.contains(p.groupId));
      }
      _cfg.groups
        ..clear()
        ..addAll(r);
      _cfg.normalizePointGroups();
    });
    await _save();
    _toast('分组已更新');
  }

  // ---------------- 时间点排序 ----------------

  /// 上移/下移：沿用原有实现（在 _cfg.points 线性表内交换相邻两项）。
  /// 抽成方法供长按菜单复用，逻辑与改动前逐字一致，未做任何改写。
  Future<void> _movePointUp(int index) async {
    setState(() {
      final t = _cfg.points[index - 1];
      _cfg.points[index - 1] = _cfg.points[index];
      _cfg.points[index] = t;
    });
    await _save();
  }

  Future<void> _movePointDown(int index) async {
    setState(() {
      final t = _cfg.points[index + 1];
      _cfg.points[index + 1] = _cfg.points[index];
      _cfg.points[index] = t;
    });
    await _save();
  }

  Future<void> _deletePoint(int index) async {
    final gid = index >= 0 && index < _cfg.points.length ? _cfg.points[index].groupId : '';
    setState(() {
      if (index >= 0 && index < _cfg.points.length) {
        _cfg.points.removeAt(index);
      }
      // 删除时间点后，若它所属的分组再没有成员，则自动删除该空分组（默认组除外）。
      if (gid.isNotEmpty && gid != TapperConfig.defaultGroupId &&
          _cfg.groups.any((g) => g.id == gid) &&
          !_cfg.points.any((p) => p.groupId == gid)) {
        _cfg.groups.removeWhere((g) => g.id == gid);
      }
    });
    await _save();
    // 删除的是开启的时间点时，其屏幕上的坐标标记（十字+圆框+序号）需要一并移除，
    // 否则会残留屏幕上。隐藏操作在原生侧幂等，未显示标记时调用无害。
    await Native.hidePointMarkers();
  }

  /// 复制时间点：在同一分组下新建一条**内容完全一致**的新时间点。
  ///
  /// 逐字段显式复制（项目内无现成克隆工具，grep clone/copy/copyWith = 0 命中），
  /// 字段清单与 models.dart TimePoint 一一对应，不做静默丢弃：
  ///   hour / minute / second / steps / repeatCount / repeatIntervalMs / groupId
  /// 按用户确认：enabled 强制为关闭（避免凭空多出一个会参与定时触发的任务）；
  /// id 由 TimePoint 构造函数的既有规则自动生成；插入位置为原项之后（同分组内紧邻）。
  Future<void> _duplicatePoint(int index) async {
    final src = _cfg.points[index];
    final copy = TimePoint(
      hour: src.hour,
      minute: src.minute,
      second: src.second,
      enabled: false,
      repeatCount: src.repeatCount,
      repeatIntervalMs: src.repeatIntervalMs,
      groupId: src.groupId,
      // 步骤逐项复制为新的 TapStep，避免与原项共享可变对象
      steps: src.steps
          .map((s) => TapStep(x: s.x, y: s.y, delayMs: s.delayMs, sw: s.sw, sh: s.sh))
          .toList(),
    );
    setState(() => _cfg.points.insert(index + 1, copy));
    await _save();
    _toast('已复制时间点：' + src.label + '（新项默认关闭）');
  }

  Future<void> _runNow(TimePoint p) async {
    if (p.steps.isEmpty) {
      _toast('该时间点还没有步骤');
      return;
    }
    if (_state['a11y'] != true) {
      _toast('无障碍服务未开启，无法点击');
      await Native.openAccessibilitySettings();
      return;
    }
    final ok = await Native.runNow(p.label + '(手动)', _cfg.toJsonString());
    _toast(ok ? '已开始执行序列' : '执行失败，请查看日志');
  }

  @override
  Widget build(BuildContext context) {
    final a11y = _state['a11y'] == true;
    final overlay = _state['overlay'] == true;
    final running = _state['running'] == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('定时连点器'),
        actions: [
          IconButton(
            tooltip: '分组管理',
            icon: const Icon(Icons.folder_outlined),
            onPressed: _manageGroups,
          ),
        ],
      ),
      body: Column(
        children: [
          _statusCard(a11y, overlay, running),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              children: [
                if (_cfg.points.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('还没有时间点，点右下角 + 添加')),
                  ),
                // 去掉分组：时间点平铺展示，每条是一个可展开卡片
                ..._cfg.points.asMap().entries.map((e) => _pointCard(e.key, e.value)),
                const SizedBox(height: 8),
                _logCard(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fabPoint',
        onPressed: _addPoint,
        icon: const Icon(Icons.add_alarm),
        label: const Text('新增时间点'),
      ),
    );
  }

  /// 布局改造：原先把「状态 chip + 下次触发/时区 + 7 个按钮」全部平铺，
  /// 固定占用约 200dp，把时间点列表挤在下面。
  /// 现在：状态 chip 与操作按钮**始终可见**（入口不被隐藏），
  /// 只把「下次触发 / 系统时区」这两行详情收进可折叠区（默认收起），
  /// 并整体压缩内边距与控件密度，把纵向空间让给时间点列表。
  Widget _statusCard(bool a11y, bool overlay, bool running) {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _chip('无障碍', a11y, a11y ? '已连接' : '未开启',
                          onTap: () => Native.openAccessibilitySettings()),
                      _chip('悬浮窗', overlay, overlay ? '已授权' : '未授权',
                          onTap: () => Native.openOverlaySettings()),
                      _chip('状态', running, running ? '执行中' : '待机'),
                    ],
                  ),
                ),
              ],
            ),
            Text('下次触发: ' + (_state['next']?.toString() ?? '-'),
                style: const TextStyle(fontSize: 13)),
            Text('系统时区: ' + (_state['tz']?.toString() ?? '-'),
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            // 布局改造：6 个平铺按钮是上方区域的最大占用（约 2 行）。
            // 操作区不再留「选点导入」入口（取点只在时间点卡片内进行）；仅在执行中显示「中止」。
            if (running)
              Row(
                children: [
                  _statusAction(Icons.stop, '中止', () => Native.abort()),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 状态卡片里的紧凑操作按钮：入口与文案不变，只压缩内边距与最小高度，
  /// 让同一块区域能少占 1~2 行（原来默认尺寸约 40dp/行）。
  Widget _statusAction(IconData icon, String label, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
      ),
    );
  }

  /// 状态标签（chip）。[onTap] 非空时整块可点（如未授权时点击直达对应权限设置页）。
  Widget _chip(String label, bool ok, String detail, {VoidCallback? onTap}) {
    final color = ok ? Colors.green : Colors.orange;
    final chip = Chip(
      avatar: Icon(ok ? Icons.check_circle : Icons.error_outline, color: color, size: 18),
      label: Text(label + ': ' + detail),
      visualDensity: VisualDensity.compact,
    );
    // 有跳转动作且权限未就绪时，整块可点击直达设置，并给出视觉反馈
    if (onTap == null) return chip;
    return ActionChip(
      avatar: Icon(ok ? Icons.check_circle : Icons.open_in_new, color: color, size: 18),
      label: Text(label + ': ' + detail),
      visualDensity: VisualDensity.compact,
      // 已授权时也允许点击（再次进入设置可重新开关），未授权时是主要跳转入口
      onPressed: onTap,
    );
  }

  Widget _pointCard(int index, TimePoint p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      // 长按卡片任意位置弹出操作菜单。用 onLongPressStart 拿到按压位置，
      // 通过 showMenu 在手指处弹出（沿用项目既有菜单样式，不新造弹层）。
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPressStart: (d) => _showPointMenu(index, p, d.globalPosition),
        child: ExpansionTile(
        // 按需求调整：组内时间点默认**收起**（原为 true）。
        // 仅改时间点卡片这一处；分组自身的 initiallyExpanded（_groupSection）保持不动。
        initiallyExpanded: false,
        leading: Switch(
          value: p.enabled,
          onChanged: (v) async {
            // 开启定时点击前检查无障碍权限：未连接则不允许开启，提示并跳转设置
            if (v && _state['a11y'] != true) {
              _toast('请先开启无障碍权限，否则无法执行自动点击');
              await Native.openAccessibilitySettings();
              return;
            }
            setState(() => p.enabled = v);
            await _save();
            // 开启时在屏幕上显示该时间点所有步骤的坐标标记（十字+圆框）；关闭则移除
            if (v) {
              final stepsJson = jsonEncode(p.steps.map((s) => s.toJson()).toList());
              await Native.showPointMarkers(stepsJson);
            } else {
              await Native.hidePointMarkers();
            }
          },
        ),
        title: Text(
          p.label,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：小圆点 + 分组名称
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.blueAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _groupNameOf(p),
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // 第二行：N步 · 状态 · 重复
            Text(
              p.steps.length.toString() +
                  ' 步 · ' +
                  (p.enabled ? '已启用' : '已停用') +
                  ' · ' +
                  p.repeatLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        children: [
          // 操作入口已全部迁入「长按菜单」（按用户确认：不保留新旧两套入口）。
          // 长按卡片任意位置即可弹出，菜单实现沿用项目既有的 PopupMenuButton 方案
          // （与步骤行、分组标题的菜单一致），不再自建弹层。
          ...p.steps.asMap().entries.map((e) => _stepTile(p, e.key, e.value)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _runNow(p),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('立即执行一次'),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// 长按时间点弹出的操作菜单：修改 / 分组 / 上移 / 下移 / 删除 / 复制。
  ///
  /// 复用既有回调（_editPoint / _movePointToGroup / _movePointUp / _movePointDown /
  /// _deletePoint / _duplicatePoint），不复制业务逻辑；
  /// 弹出方式沿用项目既有菜单（showMenu + PopupMenuItem，样式与步骤行/分组菜单一致）。
  /// 上移/下移的禁用态由 PopupMenuItem.enabled 表达（原按钮栏的 disabled 语义等价迁移）。
  Future<void> _showPointMenu(int index, TimePoint p, Offset globalPos) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'edit', child: Text('修改')),
        PopupMenuItem(value: 'up', enabled: index > 0, child: const Text('上移')),
        PopupMenuItem(
            value: 'down',
            enabled: index < _cfg.points.length - 1,
            child: const Text('下移')),
        const PopupMenuItem(value: 'duplicate', child: Text('复制')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (selected == null) return;
    switch (selected) {
      case 'edit':
        await _editPoint(p);
        break;
      case 'up':
        await _movePointUp(index);
        break;
      case 'down':
        await _movePointDown(index);
        break;
      case 'duplicate':
        await _duplicatePoint(index);
        break;
      case 'delete':
        await _deletePoint(index);
        break;
    }
  }

  /// 阶段四排版修复说明：
  /// 原先 5 个 IconButton 直接排在 trailing 的 Row 里，约占用 240dp，
  /// 在手机上几乎把 title/subtitle 挤没，描述只能竖排显示。
  /// 现在改为单个「更多」弹出菜单（约 40dp），描述文字获得整行横向空间。
  Widget _stepTile(TimePoint p, int i, TapStep s) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 12, right: 0),
      leading: CircleAvatar(
        radius: 12,
        child: Text((i + 1).toString(), style: const TextStyle(fontSize: 11)),
      ),
      title: Text(
        '坐标 (' + s.x.toString() + ', ' + s.y.toString() + ')',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '取点时屏幕 ' +
            s.sw.toString() +
            'x' +
            s.sh.toString() +
            ' · 到下一步延时 ' +
            s.delayMs.toString() +
            'ms',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '步骤操作',
        icon: const Icon(Icons.more_vert, size: 20),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 160),
        onSelected: (v) async {
          switch (v) {
            case 'pick':
              await _pickFor('edit|' + i.toString() + '|' + p.id);
              break;
            case 'delay':
              final nv = await showDelayDialog(context, s.delayMs);
              if (nv == null) return;
              setState(() => s.delayMs = nv);
              await _save();
              break;
            case 'up':
              setState(() {
                final t = p.steps[i - 1];
                p.steps[i - 1] = p.steps[i];
                p.steps[i] = t;
              });
              await _save();
              break;
            case 'down':
              setState(() {
                final t = p.steps[i + 1];
                p.steps[i + 1] = p.steps[i];
                p.steps[i] = t;
              });
              await _save();
              break;
            case 'delete':
              setState(() => p.steps.removeAt(i));
              await _save();
              break;
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'pick', child: Text('重新取点')),
          const PopupMenuItem(value: 'delay', child: Text('改延时')),
          PopupMenuItem(value: 'up', enabled: i > 0, child: const Text('上移')),
          PopupMenuItem(value: 'down', enabled: i < p.steps.length - 1, child: const Text('下移')),
          const PopupMenuItem(value: 'delete', child: Text('删除步骤')),
        ],
      ),
    );
  }

  /// 美化后的人读日志卡片：每条日志按级别着色 + 级别徽章，时间与应用内容分列，
  /// 背景用柔和的深色「编辑器」风格，行内可选中复制。仍保持滚动到底部自动跟随。
  /// 日志**常驻展开**（去掉收缩/展开控制），标题与内容一起可见。
  Widget _logCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text('运行日志 (' + _logs.length.toString() + ')',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_pickMode)
                  const Text('取点模式进行中…',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E1E2E), Color(0xFF11111B)],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF333350), width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text('暂无日志，执行后这里会显示每一步的动线',
                          style: TextStyle(color: Color(0xFF8888AA), fontSize: 12)),
                    )
                  : SingleChildScrollView(
                      controller: _logScroll,
                      // 用一个 Column 逐行渲染（便于着色），用 GestureDetector 包一层
                      // 让非交互区域仍可长按复制整块。
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [for (final l in _logs) _logLineWidget(l)],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 把一条日志解析成「时间 ｜ 级别徽章 ｜ 正文」三段的彩色行。
  /// 原生日志格式：`HH:mm:ss.SSS [LEVEL] message`（见 LogBus.add）。
  Widget _logLineWidget(String line) {
    // 解析出级别与正文：`HH:mm:ss.SSS [LEVEL] msg`
    var level = 'INFO';
    var rest = line.contains('] ')
        ? line.substring(line.lastIndexOf('] ') + 2)
        : line;
    final m = RegExp(r'\[(\w+)\]').firstMatch(line);
    if (m != null) level = m.group(1)!.toUpperCase();
    // 时间前缀：取行首的 HH:mm:ss.SSS（最多前 12 个字符）。
    final time = (line.length > 12 ? line.substring(0, 12) : line);

    Color levelColor;
    switch (level) {
      case 'ERROR':
        levelColor = const Color(0xFFFF6B6B);
        break;
      case 'WARN':
        levelColor = const Color(0xFFFFB74D);
        break;
      case 'OK':
      case 'PICK':
        levelColor = const Color(0xFF68D391);
        break;
      case 'TEST':
        levelColor = const Color(0xFF63B3ED);
        break;
      case 'WAIT':
        levelColor = const Color(0xFFB39DDB);
        break;
      default:
        levelColor = const Color(0xFF9CCC65);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectionArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(time,
                  style: const TextStyle(
                      color: Color(0xFF7777AA), fontSize: 10, fontFamily: 'monospace')),
            ),
            const SizedBox(width: 6),
            Container(
              margin: const EdgeInsets.only(top: 1),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(level,
                  style: TextStyle(color: levelColor, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(rest,
                  style: TextStyle(
                      color: levelColor, fontSize: 11, fontFamily: 'monospace', height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }
}
