import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme.dart';
import '../../../core/utils/task_formatters.dart';
import '../../../core/voice/voice_player_service.dart';
import '../../../core/voice/voice_providers.dart';
import '../../../core/voice/voice_recorder_service.dart';
import '../application/task_providers.dart';
import '../domain/task.dart';
import '../domain/task_voice_note.dart';

class TaskEditorPage extends ConsumerStatefulWidget {
  const TaskEditorPage({this.taskId, super.key});

  final int? taskId;

  bool get isEditing => taskId != null;

  @override
  ConsumerState<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends ConsumerState<TaskEditorPage> {
  final TextEditingController _titleController = TextEditingController();

  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  bool _isAllDay = true;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);
  TaskReminderKey _reminderKey = TaskReminderKey.day9am;
  TaskRepeatKey _repeatKey = TaskRepeatKey.none;
  TaskStatus _status = TaskStatus.pending;
  DateTime _createdAt = DateTime.now();
  DateTime? _completedAt;
  bool _isSaving = false;
  bool _isLoadingTask = false;
  bool _hasUserEdited = false;

  TaskVoiceNote? _existingVoiceNote;
  String? _pendingVoicePath;
  int? _pendingVoiceDuration;
  bool _voiceMarkedForDelete = false;

  bool _isRecording = false;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTimer;

  static const List<TaskReminderKey> _allDayReminderOptions = <TaskReminderKey>[
    TaskReminderKey.none,
    TaskReminderKey.day9am,
    TaskReminderKey.dayNoon,
    TaskReminderKey.day6pm,
    TaskReminderKey.dayBefore9am,
  ];

  static const List<TaskReminderKey> _timedReminderOptions = <TaskReminderKey>[
    TaskReminderKey.none,
    TaskReminderKey.atStart,
    TaskReminderKey.before5m,
    TaskReminderKey.before10m,
    TaskReminderKey.before30m,
    TaskReminderKey.before1h,
  ];

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_markEdited);
    if (widget.isEditing) {
      _loadTask();
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_markEdited);
    _titleController.dispose();
    _recordingTimer?.cancel();
    if (_isRecording) {
      ref.read(voiceRecorderServiceProvider).cancelRecording();
    }
    if (_pendingVoicePath != null) {
      _safeDeleteFile(_pendingVoicePath!);
    }
    super.dispose();
  }

  bool get _isDirty {
    if (_hasUserEdited) {
      return true;
    }
    return _pendingVoicePath != null || _voiceMarkedForDelete;
  }

  void _markEdited() {
    if (!_hasUserEdited) {
      setState(() {
        _hasUserEdited = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<TaskReminderKey> reminderOptions = _isAllDay
        ? _allDayReminderOptions
        : _timedReminderOptions;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        final NavigatorState navigator = Navigator.of(context);
        final bool confirm = await _confirmDiscardChanges();
        if (confirm && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        body: Column(
          children: <Widget>[
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    ScheduleBoardPalette.headerStart,
                    ScheduleBoardPalette.headerEnd,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          _HeaderIconButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: _handleBackPressed,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  widget.isEditing ? '编辑待办' : '新建待办',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.headlineSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.isEditing
                                      ? '调整标题、时间、提醒、重复和录音备注'
                                      : '本地保存到平板，可附加一段录音备注',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _isSaving || _isLoadingTask
                                ? null
                                : _saveTask,
                            icon: Icon(
                              _isSaving
                                  ? Icons.hourglass_top_rounded
                                  : Icons.check_circle_rounded,
                            ),
                            label: Text(_isSaving ? '保存中' : '保存'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          _SummaryPill(
                            icon: Icons.calendar_month_rounded,
                            text: formatHeadlineDate(_selectedDate),
                          ),
                          _SummaryPill(
                            icon: Icons.notifications_active_outlined,
                            text: _reminderLabel(_reminderKey),
                          ),
                          _SummaryPill(
                            icon: Icons.repeat_rounded,
                            text: _repeatLabel(_repeatKey),
                          ),
                          if (_hasVoice)
                            const _SummaryPill(
                              icon: Icons.graphic_eq_rounded,
                              text: '已附录音备注',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoadingTask
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: <Widget>[
                        _SectionCard(
                          title: '任务内容',
                          subtitle: '先记录核心信息，控制在一句话内最清晰。',
                          child: TextField(
                            controller: _titleController,
                            maxLength: 50,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: '待办标题',
                              hintText: '请输入待办内容',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionCard(
                          title: '时间与提醒',
                          subtitle: '一期先做基础日期、时间、提醒和简单重复。',
                          child: Column(
                            children: <Widget>[
                              _ActionTile(
                                icon: Icons.calendar_today_outlined,
                                title: '开始日期',
                                subtitle: formatHeadlineDate(_selectedDate),
                                onTap: _pickDate,
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                title: const Text(
                                  '全天待办',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: const Text(
                                  '开启后隐藏开始时间和结束时间',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                value: _isAllDay,
                                onChanged: (bool value) {
                                  final List<TaskReminderKey> nextOptions = value
                                      ? _allDayReminderOptions
                                      : _timedReminderOptions;
                                  _markEdited();
                                  setState(() {
                                    _isAllDay = value;
                                    if (!nextOptions.contains(_reminderKey)) {
                                      _reminderKey = value
                                          ? TaskReminderKey.day9am
                                          : TaskReminderKey.before10m;
                                    }
                                  });
                                },
                              ),
                              if (!_isAllDay) ...<Widget>[
                                const Divider(height: 1),
                                _ActionTile(
                                  icon: Icons.access_time_rounded,
                                  title: '开始时间',
                                  subtitle: _startTime.format(context),
                                  onTap: () => _pickTime(isStartTime: true),
                                ),
                                const Divider(height: 1),
                                _ActionTile(
                                  icon: Icons.timelapse_outlined,
                                  title: '结束时间',
                                  subtitle: _endTime.format(context),
                                  onTap: () => _pickTime(isStartTime: false),
                                ),
                              ],
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                                child: DropdownButtonFormField<TaskReminderKey>(
                                  initialValue: reminderOptions.contains(_reminderKey)
                                      ? _reminderKey
                                      : reminderOptions.first,
                                  decoration: const InputDecoration(
                                    labelText: '提醒',
                                    helperText: '全天默认当天 09:00；非全天默认提前 10 分钟',
                                  ),
                                  items: reminderOptions
                                      .map(
                                        (TaskReminderKey key) =>
                                            DropdownMenuItem<TaskReminderKey>(
                                              value: key,
                                              child: Text(
                                                _reminderLabel(key),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                      )
                                      .toList(),
                                  onChanged: (TaskReminderKey? value) {
                                    if (value == null) {
                                      return;
                                    }
                                    _markEdited();
                                    setState(() {
                                      _reminderKey = value;
                                    });
                                  },
                                ),
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                                child: DropdownButtonFormField<TaskRepeatKey>(
                                  initialValue: _repeatKey,
                                  decoration: const InputDecoration(
                                    labelText: '重复',
                                    helperText: 'V1 先做不重复 / 每天 / 每周 / 每月',
                                  ),
                                  items: TaskRepeatKey.values
                                      .map(
                                        (TaskRepeatKey key) =>
                                            DropdownMenuItem<TaskRepeatKey>(
                                              value: key,
                                              child: Text(
                                                _repeatLabel(key),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                      )
                                      .toList(),
                                  onChanged: (TaskRepeatKey? value) {
                                    if (value == null) {
                                      return;
                                    }
                                    _markEdited();
                                    setState(() {
                                      _repeatKey = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionCard(
                          title: '录音备注',
                          subtitle: '本地录制并保存在平板，仅本机播放，不上云。',
                          child: _buildVoiceSection(),
                        ),
                        if (widget.isEditing) ...<Widget>[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _isSaving ? null : _deleteTask,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('删除待办'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFB44C22),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSection() {
    if (_isRecording) {
      return _RecordingPanel(
        elapsed: _recordingElapsed,
        onStop: _stopRecording,
        onCancel: _cancelRecording,
      );
    }

    if (_pendingVoicePath != null) {
      return _VoicePlaybackPanel(
        filePath: _pendingVoicePath!,
        durationMillis: _pendingVoiceDuration ?? 0,
        labelPrefix: '新录制',
        primaryActionLabel: '重新录制',
        onPrimaryAction: _startRecording,
        onDelete: _discardPendingVoice,
      );
    }

    if (_existingVoiceNote != null && !_voiceMarkedForDelete) {
      return _VoicePlaybackPanel(
        filePath: _existingVoiceNote!.localPath,
        durationMillis: _existingVoiceNote!.durationMillis,
        labelPrefix: '已保存',
        primaryActionLabel: '重新录制',
        onPrimaryAction: _startRecording,
        onDelete: _markExistingVoiceForDelete,
      );
    }

    return _VoiceEmptyPanel(onStart: _startRecording);
  }

  bool get _hasVoice {
    if (_pendingVoicePath != null) {
      return true;
    }
    return _existingVoiceNote != null && !_voiceMarkedForDelete;
  }

  Future<void> _startRecording() async {
    final VoiceRecorderService recorder = ref.read(voiceRecorderServiceProvider);

    bool granted = await recorder.hasPermission();
    if (!granted) {
      final PermissionStatus status = await Permission.microphone.request();
      granted = status.isGranted;
    }
    if (!mounted) {
      return;
    }
    if (!granted) {
      _showMessage('未获得麦克风权限，无法录音');
      return;
    }

    await ref.read(voicePlayerServiceProvider).stop();

    if (_pendingVoicePath != null) {
      _safeDeleteFile(_pendingVoicePath!);
    }

    try {
      await recorder.startTempRecording();
    } catch (_) {
      _showMessage('录音启动失败，请稍后重试');
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isRecording = true;
      _recordingElapsed = Duration.zero;
      _pendingVoicePath = null;
      _pendingVoiceDuration = null;
    });
    _markEdited();

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _recordingElapsed = Duration(seconds: timer.tick);
      });
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final VoiceRecordingResult? result =
        await ref.read(voiceRecorderServiceProvider).stopRecording();

    if (!mounted) {
      return;
    }

    if (result == null) {
      setState(() {
        _isRecording = false;
        _recordingElapsed = Duration.zero;
      });
      _showMessage('录音失败，请重试');
      return;
    }

    setState(() {
      _isRecording = false;
      _recordingElapsed = Duration.zero;
      _pendingVoicePath = result.filePath;
      _pendingVoiceDuration = result.durationMillis;
    });
    _markEdited();
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await ref.read(voiceRecorderServiceProvider).cancelRecording();
    if (!mounted) {
      return;
    }
    setState(() {
      _isRecording = false;
      _recordingElapsed = Duration.zero;
    });
  }

  void _discardPendingVoice() {
    if (_pendingVoicePath != null) {
      _safeDeleteFile(_pendingVoicePath!);
    }
    setState(() {
      _pendingVoicePath = null;
      _pendingVoiceDuration = null;
    });
    _markEdited();
  }

  void _markExistingVoiceForDelete() {
    setState(() {
      _voiceMarkedForDelete = true;
    });
    _markEdited();
  }

  Future<void> _loadTask() async {
    setState(() {
      _isLoadingTask = true;
    });

    final Task? task = await ref.read(taskDetailsProvider(widget.taskId!).future);
    if (!mounted) {
      return;
    }

    if (task == null) {
      _showMessage('任务不存在或已被删除');
      Navigator.of(context).pop();
      return;
    }

    final TaskVoiceNote? voiceNote =
        await ref.read(taskVoiceNoteProvider(widget.taskId!).future);
    if (!mounted) {
      return;
    }

    _titleController.removeListener(_markEdited);
    _titleController.text = task.title;
    _titleController.addListener(_markEdited);

    setState(() {
      _selectedDate = DateUtils.dateOnly(task.startDate);
      _isAllDay = task.isAllDay;
      _startTime = _timeOfDayFromMinutes(task.startTimeMinutes ?? 9 * 60);
      _endTime = _timeOfDayFromMinutes(task.endTimeMinutes ?? 10 * 60);
      _reminderKey = task.reminderKey;
      _repeatKey = task.repeatKey;
      _status = task.status;
      _createdAt = task.createdAt;
      _completedAt = task.completedAt;
      _existingVoiceNote = voiceNote;
      _hasUserEdited = false;
      _isLoadingTask = false;
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );

    if (picked == null) {
      return;
    }

    _markEdited();
    setState(() {
      _selectedDate = DateUtils.dateOnly(picked);
    });
  }

  Future<void> _pickTime({required bool isStartTime}) async {
    final TimeOfDay initialTime = isStartTime ? _startTime : _endTime;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked == null) {
      return;
    }

    _markEdited();
    setState(() {
      if (isStartTime) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _handleBackPressed() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final bool confirm = await _confirmDiscardChanges();
    if (confirm && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('当前内容尚未保存'),
          content: const Text('返回后未保存的修改会被放弃，是否继续？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('放弃'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _saveTask() async {
    final String title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('请先输入待办标题');
      return;
    }

    if (!_isAllDay) {
      final int startMinutes = _minutesOfDay(_startTime);
      final int endMinutes = _minutesOfDay(_endTime);
      if (endMinutes <= startMinutes) {
        _showMessage('结束时间需要晚于开始时间');
        return;
      }
    }

    if (_isRecording) {
      _showMessage('请先结束当前录音');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final DateTime now = DateTime.now();
      final Task task = Task(
        id: widget.taskId,
        title: title,
        startDate: _selectedDate,
        isAllDay: _isAllDay,
        startTimeMinutes: _isAllDay ? null : _minutesOfDay(_startTime),
        endTimeMinutes: _isAllDay ? null : _minutesOfDay(_endTime),
        reminderKey: _reminderKey,
        repeatKey: _repeatKey,
        status: _status,
        createdAt: _createdAt,
        updatedAt: now,
        completedAt: _completedAt,
      );

      final int taskId;
      if (widget.isEditing) {
        await ref.read(taskMutationControllerProvider).updateTask(task);
        taskId = widget.taskId!;
      } else {
        taskId = await ref.read(taskMutationControllerProvider).createTask(task);
      }

      await _persistVoiceChanges(taskId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEditing ? '待办已更新' : '待办已保存'),
        ),
      );
      _hasUserEdited = false;
      _voiceMarkedForDelete = false;
      _pendingVoicePath = null;
      _pendingVoiceDuration = null;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        _showMessage('保存失败，请稍后重试');
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _persistVoiceChanges(int taskId) async {
    final TaskMutationController controller =
        ref.read(taskMutationControllerProvider);

    if (_voiceMarkedForDelete && _existingVoiceNote != null) {
      await controller.deleteVoiceNote(taskId);
      _existingVoiceNote = null;
    }

    if (_pendingVoicePath != null) {
      final String moved = await VoiceRecorderService.moveToPersistent(
        tempPath: _pendingVoicePath!,
        taskId: taskId,
      );
      await controller.upsertVoiceNote(
        taskId: taskId,
        localPath: moved,
        durationMillis: _pendingVoiceDuration ?? 0,
      );
    }
  }

  Future<void> _deleteTask() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await ref
          .read(taskMutationControllerProvider)
          .softDeleteTaskById(widget.taskId!);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('待办已删除')));
      _hasUserEdited = false;
      _voiceMarkedForDelete = false;
      _pendingVoicePath = null;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        _showMessage('删除失败，请稍后重试');
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _safeDeleteFile(String filePath) {
    () async {
      try {
        final File file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }();
  }

  int _minutesOfDay(TimeOfDay time) {
    return time.hour * 60 + time.minute;
  }

  TimeOfDay _timeOfDayFromMinutes(int minutes) {
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  String _reminderLabel(TaskReminderKey key) {
    return switch (key) {
      TaskReminderKey.none => '不提醒',
      TaskReminderKey.day9am => '当天 09:00',
      TaskReminderKey.dayNoon => '当天 12:00',
      TaskReminderKey.day6pm => '当天 18:00',
      TaskReminderKey.dayBefore9am => '前一天 09:00',
      TaskReminderKey.atStart => '开始时',
      TaskReminderKey.before5m => '提前 5 分钟',
      TaskReminderKey.before10m => '提前 10 分钟',
      TaskReminderKey.before30m => '提前 30 分钟',
      TaskReminderKey.before1h => '提前 1 小时',
      TaskReminderKey.custom => '自定义',
    };
  }

  String _repeatLabel(TaskRepeatKey key) {
    return switch (key) {
      TaskRepeatKey.none => '不重复',
      TaskRepeatKey.daily => '每天',
      TaskRepeatKey.weekly => '每周',
      TaskRepeatKey.monthly => '每月',
    };
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120E1F36),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ScheduleBoardPalette.mutedText,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _VoiceEmptyPanel extends StatelessWidget {
  const _VoiceEmptyPanel({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.keyboard_voice_outlined),
              SizedBox(width: 10),
              Text(
                '尚未录制备注',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '点击下方按钮开始录音，文件保存在本机，仅本设备可播放。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ScheduleBoardPalette.mutedText,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.fiber_manual_record_rounded),
            label: const Text('开始录音'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD3544B),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({
    required this.elapsed,
    required this.onStop,
    required this.onCancel,
  });

  final Duration elapsed;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5C7B1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.mic_rounded,
                color: Color(0xFFD3544B),
              ),
              const SizedBox(width: 10),
              Text(
                '正在录音',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFB44C22),
                ),
              ),
              const Spacer(),
              Text(
                formatVoiceDuration(elapsed.inMilliseconds),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFB44C22),
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('结束录音'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
                label: const Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoicePlaybackPanel extends ConsumerWidget {
  const _VoicePlaybackPanel({
    required this.filePath,
    required this.durationMillis,
    required this.labelPrefix,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    required this.onDelete,
  });

  final String filePath;
  final int durationMillis;
  final String labelPrefix;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VoicePlayerService player = ref.watch(voicePlayerServiceProvider);

    return StreamBuilder<VoicePlaybackSnapshot>(
      stream: player.stateStream,
      builder: (BuildContext context, AsyncSnapshot<VoicePlaybackSnapshot> snapshot) {
        final VoicePlaybackSnapshot? snap = snapshot.data;
        final bool playing = snap?.isActiveFor(filePath) ?? false;
        final Duration position =
            (snap?.path == filePath ? snap?.position : null) ?? Duration.zero;
        final int total = durationMillis > 0
            ? durationMillis
            : (snap?.path == filePath ? snap?.duration.inMilliseconds : null) ?? 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F8FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFCFE0FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.graphic_eq_rounded,
                    color: ScheduleBoardPalette.tealAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$labelPrefix · ${formatVoiceDuration(total)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    formatVoiceDuration(position.inMilliseconds),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ScheduleBoardPalette.mutedText,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () async {
                      if (playing) {
                        await player.stop();
                      } else {
                        await player.playFile(filePath);
                      }
                    },
                    icon: Icon(
                      playing
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(playing ? '停止' : '播放'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ScheduleBoardPalette.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onPrimaryAction,
                    icon: const Icon(Icons.fiber_manual_record_rounded),
                    label: Text(primaryActionLabel),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFB44C22),
                    ),
                    tooltip: '删除录音',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
