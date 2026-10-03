import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// 时间点「新增 / 修改」对话框的返回值。
class TimeEditResult {
  final int hour;
  final int minute;
  final int second;
  final int repeatCount;
  final int repeatIntervalMs;

  /// 多选集合（第 3 项）。空列表 = 沿用单值字段。
  final List<int> hours;
  final List<int> minutes;
  final List<int> seconds;

  /// 所选分组 id。空字符串 = 默认组「未分组」。
  final String groupId;

  /// 用户在对话框里选择「新建分组」时填入的新分组名；否则为 null。
  /// 调用方拿到后据此新建分组并把时间点归入。
  final String? newGroupName;

  TimeEditResult({
    required this.hour,
    required this.minute,
    required this.second,
    required this.repeatCount,
    required this.repeatIntervalMs,
    this.hours = const <int>[],
    this.minutes = const <int>[],
    this.seconds = const <int>[],
    this.groupId = '',
    this.newGroupName,
  });

  /// 展开后的组合数（用于上限校验与预览）。
  int get comboCount {
    final h = hours.isEmpty ? 1 : hours.length;
    final m = minutes.isEmpty ? 1 : minutes.length;
    final s = seconds.isEmpty ? 1 : seconds.length;
    return h * m * s;
  }
}

/// 编辑「到下一步的延时（毫秒）」
Future<int?> showDelayDialog(BuildContext context, int current) {
  final c = TextEditingController(text: current.toString());
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('到下一步的延时（毫秒）'),
      content: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofocus: true,
        decoration: const InputDecoration(hintText: '例如 300'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final v = int.tryParse(c.text.trim());
            Navigator.pop(ctx, v ?? current);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 手动输入坐标（不依赖悬浮窗取点的兜底方式）
Future<List<int>?> showCoordDialog(BuildContext context, int x, int y) {
  final cx = TextEditingController(text: x.toString());
  final cy = TextEditingController(text: y.toString());
  return showDialog<List<int>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('手动输入坐标'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: cx,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
            decoration: const InputDecoration(labelText: 'X'),
          ),
          TextField(
            controller: cy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
            decoration: const InputDecoration(labelText: 'Y'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final a = int.tryParse(cx.text.trim());
            final b = int.tryParse(cy.text.trim());
            if (a == null || b == null) return;
            Navigator.pop(ctx, [a, b]);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 新增 / 修改时间点：选择小时（含「每小时」重复）与分、秒，并设置重复次数与重复间隔。
///
/// [existing] 为 null 时是「新增」，否则是「修改」（预填当前值）。
/// [groups] 为当前全部分组，用于本时间点归属分组的选择（也支持新建分组）。
Future<TimeEditResult?> showTimeDialog(BuildContext context,
    {TimePoint? existing, List<PointGroup>? groups}) {
  final isEdit = existing != null;
  final groupList = groups ?? <PointGroup>[];

  // 分组选择：**必须**选一个真实分组（用户要求禁止「未分组」）。
  // 因此下拉只列出自定义分组 + 「新建分组…」，不出现「未分组」选项。
  const newGroupMarker = '__new_group__';
  final realGroups = groupList.where((g) => g.id != TapperConfig.defaultGroupId).toList();
  final existingInReal = existing != null &&
      realGroups.any((g) => g.id == existing.groupId);
  // 新增或现有点在默认组时，默认进入「新建分组」；否则预选现有点所在的真实分组。
  var isNewGroup = !existingInReal;
  final existingGroupId = existing?.groupId ?? '';
  var selGroupId = existingInReal
      ? existingGroupId
      : (realGroups.isEmpty ? '' : realGroups.first.id);
  final newGroupNameCtl = TextEditingController(text: '新分组');

  // 单时间点（时/分/秒 三滚轮）。编辑时若旧数据是多选/每小时，取集合里的「首个值」作为滚轮初值；
  // 新增时默认停在「当前时间」。
  final now = DateTime.now();
  final initHour = existing != null
      ? (existing.effectiveHours.isNotEmpty
          ? existing.effectiveHours.first
          : (existing.hour >= 0 ? existing.hour : now.hour))
      : now.hour;
  final initMinute = existing != null
      ? (existing.effectiveMinutes.isNotEmpty
          ? existing.effectiveMinutes.first
          : existing.minute)
      : now.minute;
  final initSecond = existing != null
      ? (existing.effectiveSeconds.isNotEmpty
          ? existing.effectiveSeconds.first
          : existing.second)
      : now.second;

  // 三个滚轮各自的滚动控制器（初值 = 当前选择）
  final hourCtl = FixedExtentScrollController(initialItem: initHour);
  final minuteCtl = FixedExtentScrollController(initialItem: initMinute);
  final secondCtl = FixedExtentScrollController(initialItem: initSecond);

  // 当前选中的值（随滚轮更新，确定时读取）
  var selHour = initHour;
  var selMinute = initMinute;
  var selSecond = initSecond;

  final countCtl = TextEditingController(text: (existing?.repeatCount ?? 1).toString());
  final intervalCtl = TextEditingController(text: (existing?.repeatIntervalMs ?? 0).toString());
  String? countError;
  String? intervalError;
  String? groupError;

  return showDialog<TimeEditResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        // 实时预览：当前输入的次数与间隔
        final c = int.tryParse(countCtl.text.trim());
        final iv = int.tryParse(intervalCtl.text.trim());
        final previewCount = TimePoint.normalizeRepeatCount(c ?? 1);
        final previewInterval = TimePoint.normalizeRepeatInterval(iv ?? 0);
        final spanMs = (previewCount - 1) * previewInterval;

        return AlertDialog(
          title: Text(isEdit ? '修改时间点' : '新增时间点'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 时:分:秒 三滚轮（单选，像系统闹钟）。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _timeWheel(
                      controller: hourCtl,
                      label: '时',
                      count: 24,
                      format: (v) => v.toString().padLeft(2, '0'),
                      onChanged: (v) => setLocal(() => selHour = v),
                    ),
                    _timeWheel(
                      controller: minuteCtl,
                      label: '分',
                      count: 60,
                      format: (v) => v.toString().padLeft(2, '0'),
                      onChanged: (v) => setLocal(() => selMinute = v),
                    ),
                    _timeWheel(
                      controller: secondCtl,
                      label: '秒',
                      count: 60,
                      format: (v) => v.toString().padLeft(2, '0'),
                      onChanged: (v) => setLocal(() => selSecond = v),
                    ),
                  ],
                ),
                // 实时预览当前选定的时刻
                Text(
                  '选择时刻：' +
                      selHour.toString().padLeft(2, '0') +
                      ':' +
                      selMinute.toString().padLeft(2, '0') +
                      ':' +
                      selSecond.toString().padLeft(2, '0'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const Divider(height: 20),
                TextField(
                  controller: countCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '重复次数',
                    helperText: '1 = 只触发一次（1~' + TimePoint.maxRepeatCount.toString() + '）',
                    errorText: countError,
                  ),
                  onChanged: (_) => setLocal(() {
                    countError = null;
                  }),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: intervalCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '重复间隔（毫秒）',
                    helperText: '相邻两次触发之间的等待，0 = 立即连续执行',
                    errorText: intervalError,
                  ),
                  onChanged: (_) => setLocal(() {
                    intervalError = null;
                  }),
                ),
                const Divider(height: 16),
                // 分组：一个时间点对应一个分组（未分组归入默认组）。支持新建分组并命名。
                DropdownButtonFormField<String>(
                  initialValue: isNewGroup ? newGroupMarker : selGroupId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '所属分组'),
                  items: [
                    // 用户要求禁止「未分组」：只列自定义分组，且必须选一个
                    for (final g in realGroups)
                      DropdownMenuItem(
                          value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis)),
                    const DropdownMenuItem(value: newGroupMarker, child: Text('＋ 新建分组…')),
                  ],
                  onChanged: (v) => setLocal(() {
                    if (v == null) return;
                    if (v == newGroupMarker) {
                      isNewGroup = true;
                    } else {
                      isNewGroup = false;
                      selGroupId = v;
                    }
                    groupError = null;
                  }),
                ),
                if (isNewGroup)
                  TextField(
                    controller: newGroupNameCtl,
                    decoration: const InputDecoration(labelText: '新分组名称'),
                  ),
                if (groupError != null)
                  Text(
                    groupError!,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                const SizedBox(height: 10),
                Text(
                  previewCount <= 1
                      ? '预览：到点后只执行 1 次'
                      : '预览：共执行 ' +
                          previewCount.toString() +
                          ' 次，每次间隔 ' +
                          previewInterval.toString() +
                          'ms，整轮约 ' +
                          (spanMs / 1000).toStringAsFixed(1) +
                          ' 秒',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                // 边界处理：非法/空输入不崩溃，给出提示；越界自动夹取
                final rawCount = countCtl.text.trim();
                final rawInterval = intervalCtl.text.trim();
                final pc = rawCount.isEmpty ? null : int.tryParse(rawCount);
                final pi = rawInterval.isEmpty ? null : int.tryParse(rawInterval);
                if (pc == null) {
                  setLocal(() => countError = '请输入数字（1~' + TimePoint.maxRepeatCount.toString() + '）');
                  return;
                }
                if (pi == null) {
                  setLocal(() => intervalError = '请输入数字（0 或正整数毫秒）');
                  return;
                }
                // 分组必选：非新建分组必须有真实分组；新建分组必须命名非空且不重名。
                if (isNewGroup) {
                  final nm = newGroupNameCtl.text.trim();
                  if (nm.isEmpty) {
                    setLocal(() => groupError = '请填写新分组名称');
                    return;
                  }
                  final dup = groupList.any((g) => g.name.trim() == nm) ||
                      nm == TapperConfig.defaultGroupName;
                  if (dup) {
                    setLocal(() => groupError = '分组名「$nm」已存在，请换一个');
                    return;
                  }
                } else if (selGroupId.isEmpty) {
                  setLocal(() => groupError = '请选择一个分组或新建分组');
                  return;
                }
                Navigator.pop(
                  ctx,
                  TimeEditResult(
                    hour: selHour,
                    minute: selMinute,
                    second: selSecond,
                    repeatCount: TimePoint.normalizeRepeatCount(pc),
                    repeatIntervalMs: TimePoint.normalizeRepeatInterval(pi),
                    // 单时间点：三个集合各只含一个值
                    hours: <int>[selHour],
                    minutes: <int>[selMinute],
                    seconds: <int>[selSecond],
                    groupId: isNewGroup ? '' : selGroupId,
                    newGroupName: isNewGroup ? newGroupNameCtl.text.trim() : null,
                  ),
                );
              },
              child: Text(isEdit ? '保存' : '添加'),
            ),
          ],
        );
      },
    ),
  );
}

/// 单个时间滚轮：并排的 时 / 分 / 秒 选择器之一。
Widget _timeWheel({
  required FixedExtentScrollController controller,
  required String label,
  required int count,
  required String Function(int) format,
  required void Function(int) onChanged,
}) {
  return Expanded(
    child: Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        SizedBox(
          height: 160,
          child: CupertinoPicker(
            scrollController: controller,
            itemExtent: 32,
            diameterRatio: 1.4,
            squeeze: 1.1,
            selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
              background: Color(0x147D7D7D),
            ),
            onSelectedItemChanged: (i) {
              // 用已选值通知外部：CurrentRadii 需要实际值而不是索引
              onChanged(i);
            },
            children: [
              for (var i = 0; i < count; i++)
                Center(
                  child: Text(
                    format(i),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 分组管理对话框：新建分组、重命名已有分组。返回新的分组列表（null = 未改动）。
///
/// 所有分组（含默认组）都可删除；删除某分组后其成员由调用方一并清掉。
Future<List<PointGroup>?> showGroupManageDialog(
    BuildContext context, List<PointGroup> groups) {
  var list = List<PointGroup>.from(groups);
  String? dupError;
  return showDialog<List<PointGroup>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        /// 校验并就地标注重名（用于「新建/重命名」后即时提示）。
        void noteDup(String? newName, {int? exceptIndex}) {
          if (newName == null || newName.trim().isEmpty) return;
          final nm = newName.trim();
          for (var j = 0; j < list.length; j++) {
            if (j == exceptIndex) continue;
            if (list[j].name.trim() == nm) {
              dupError = '分组名「$nm」已存在，请换一个';
              return;
            }
          }
          dupError = null;
        }
        return AlertDialog(
          title: const Text('分组管理'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dupError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(dupError!,
                        style: const TextStyle(fontSize: 12, color: Colors.red)),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < list.length; i++)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_outlined, size: 18),
                          title: Text(list[i].name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: '重命名',
                                onPressed: () async {
                                  final name = await _promptText(
                                      ctx, '重命名分组', list[i].name);
                                  if (name == null) return;
                                  setLocal(() {
                                    list = [
                                      for (var j = 0; j < list.length; j++)
                                        j == i ? list[j].copyWith(name: name) : list[j],
                                    ];
                                    noteDup(name, exceptIndex: i);
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                tooltip: '删除分组',
                                onPressed: () => setLocal(() {
                                  list = [
                                    for (var j = 0; j < list.length; j++)
                                      if (j != i) list[j],
                                  ];
                                  dupError = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final name = await _promptText(ctx, '新建分组', '新分组');
                      if (name == null) return;
                      setLocal(() {
                        list = [...list, PointGroup(id: _newGroupId(), name: name)];
                        noteDup(name);
                      });
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建分组'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                // 分组名全局唯一：重名时不允许确定，原地报错
                final seen = <String>{};
                for (final g in list) {
                  final nm = g.name.trim();
                  if (nm.isEmpty) {
                    dupError = '分组名不能为空';
                    setLocal(() {});
                    return;
                  }
                  if (!seen.add(nm)) {
                    dupError = '分组名「$nm」已存在，请换一个';
                    setLocal(() {});
                    return;
                  }
                }
                dupError = null;
                Navigator.pop(ctx, list);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    ),
  );
}

/// 弹一个单行输入框，返回去除首尾空格后的文本（空返回 null）。
Future<String?> _promptText(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(hintText: '请输入名称'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final s = c.text.trim();
            Navigator.pop(ctx, s.isEmpty ? null : s);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

String _newGroupId() {
  final r = DateTime.now().microsecondsSinceEpoch.toString();
  final s = (DateTime.now().millisecondsSinceEpoch % 100000).toString();
  return 'g' + r + '-' + s;
}
