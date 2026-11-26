import 'dart:async';

import 'package:flutter/material.dart';
import 'package:simple_present/storage/sembast_storage.dart';
import 'package:simple_present/time_bookings_page.dart';

class TaskTimeControls extends StatefulWidget {
  const TaskTimeControls({
    super.key,
    required this.storage,
    required this.taskId,
    required this.taskText,
    this.enabled = true,
    this.onStarted,
  });

  final SembastStorage storage;
  final String taskId;
  final String taskText;
  final bool enabled;
  final VoidCallback? onStarted;

  @override
  State<TaskTimeControls> createState() => _TaskTimeControlsState();
}

class _TaskTimeControlsState extends State<TaskTimeControls> {
  Timer? _ticker;
  bool _running = false;
  bool _busy = false;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant TaskTimeControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) unawaited(_refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final timer = await widget.storage.readTaskTimer(widget.taskId);
      final bookings =
          await widget.storage.readTimeBookings(includeRunning: true);
      final seconds = bookings
          .where((booking) => booking.taskId == widget.taskId)
          .fold<int>(
              0,
              (total, booking) =>
                  total + booking.trackedSeconds + booking.bookedMinutes * 60);
      if (mounted)
        setState(() {
          _running = timer != null;
          _seconds = seconds;
        });
    } catch (_) {}
  }

  Future<void> _toggle(bool start) async {
    setState(() => _busy = true);
    try {
      if (start) {
        await widget.storage.startTaskTimer(
          taskId: widget.taskId,
          taskText: widget.taskText,
        );
        widget.onStarted?.call();
      } else {
        await widget.storage.stopTaskTimer(widget.taskId);
      }
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('time tracking failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bookManually() async {
    final booking = await showTimeBookingDialog(
      context,
      taskOptions: {widget.taskId: widget.taskText},
    );
    if (booking == null) return;
    try {
      await widget.storage.saveTimeBooking(booking);
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('booking failed')),
        );
      }
    }
  }

  Future<void> _showBookings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TimeBookingsPage(
        storage: widget.storage,
        taskOptions: {widget.taskId: widget.taskText},
        taskId: widget.taskId,
      ),
    ));
    if (mounted) await _refresh();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('reset stopwatch?'),
        content: const Text(
            'all stopwatch bookings for this task will be deleted. manual bookings will be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.storage.resetTaskTimer(widget.taskId);
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('reset failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final absoluteSeconds = _seconds.abs();
    final sign = _seconds < 0 ? '-' : '';
    final hours = (absoluteSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((absoluteSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (absoluteSeconds % 60).toString().padLeft(2, '0');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('stopwatch: $sign$hours:$minutes:$seconds'),
        IconButton(
          tooltip: 'start',
          icon: const Icon(Icons.play_arrow),
          onPressed:
              _busy || _running || !widget.enabled ? null : () => _toggle(true),
        ),
        IconButton(
          tooltip: 'stop',
          icon: const Icon(Icons.stop),
          onPressed: _busy || !_running ? null : () => _toggle(false),
        ),
        IconButton(
          tooltip: 'reset',
          icon: const Icon(Icons.restart_alt),
          onPressed: _busy || (!_running && _seconds == 0) ? null : _reset,
        ),
        IconButton(
          tooltip: 'add manual booking',
          icon: const Icon(Icons.more_time),
          onPressed: _busy ? null : _bookManually,
        ),
        IconButton(
          tooltip: 'show bookings',
          icon: const Icon(Icons.receipt_long_outlined),
          onPressed: _busy ? null : _showBookings,
        ),
      ],
    );
  }
}
