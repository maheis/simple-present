import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:simple_present/storage/sembast_storage.dart';
import 'package:simple_present/time_booking.dart';

Future<TimeBooking?> showTimeBookingDialog(
  BuildContext context, {
  TimeBooking? booking,
  required Map<String, String> taskOptions,
}) {
  return showDialog<TimeBooking>(
    context: context,
    builder: (_) => _TimeBookingDialog(
      booking: booking,
      taskOptions: taskOptions,
    ),
  );
}

class TimeBookingsPage extends StatefulWidget {
  const TimeBookingsPage({
    super.key,
    required this.storage,
    required this.taskOptions,
    this.taskId,
  });

  final SembastStorage storage;
  final Map<String, String> taskOptions;
  final String? taskId;

  @override
  State<TimeBookingsPage> createState() => _TimeBookingsPageState();
}

class _TimeBookingsPageState extends State<TimeBookingsPage> {
  late Future<List<TimeBooking>> _bookingsFuture;

  @override
  void initState() {
    super.initState();
    _bookingsFuture = widget.storage.readTimeBookings();
  }

  Future<void> _reload() async {
    final bookings = widget.storage.readTimeBookings();
    if (!mounted) return;
    setState(() {
      _bookingsFuture = bookings;
    });
    await bookings;
  }

  Future<void> _editBooking([TimeBooking? booking]) async {
    final result = await showTimeBookingDialog(
      context,
      booking: booking,
      taskOptions: widget.taskOptions,
    );
    if (result == null) return;
    await widget.storage.saveTimeBooking(result);
    await _reload();
  }

  Future<void> _deleteBooking(TimeBooking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buchung löschen?'),
        content: Text('${booking.taskText} · ${booking.bookingDate}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.storage.deleteTimeBooking(booking.id);
    await _reload();
  }

  String _durationLabel(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final hours = minutes.abs() ~/ 60;
    final remainder = minutes.abs() % 60;
    if (hours == 0) return '$sign$remainder min';
    if (remainder == 0) return '$sign$hours h';
    return '$sign$hours h $remainder min';
  }

  String _sourceLabel(String source) => switch (source) {
        'stopwatch' => 'Stoppuhr',
        'legacy' => 'Altbestand',
        _ => 'Manuell',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.taskId == null
              ? 'Zeiterfassung'
              : 'Buchungen: ${widget.taskOptions[widget.taskId] ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Buchung hinzufügen',
            onPressed: () => _editBooking(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: FutureBuilder<List<TimeBooking>>(
        future: _bookingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text(
                    'Buchungen konnten nicht geladen werden: ${snapshot.error}'));
          }
          final bookings = (snapshot.data ?? const <TimeBooking>[])
              .where((booking) =>
                  widget.taskId == null || booking.taskId == widget.taskId)
              .toList();
          if (bookings.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => _editBooking(),
                icon: const Icon(Icons.add),
                label: const Text('Erste Buchung erfassen'),
              ),
            );
          }
          final totalMinutes = bookings.fold<int>(
              0,
              (total, booking) =>
                  total +
                  booking.bookedMinutes +
                  ((booking.trackedSeconds + 59) ~/ 60));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '${bookings.length} ${bookings.length == 1 ? 'Buchung' : 'Buchungen'} · ${_durationLabel(totalMinutes)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 28,
                        columns: const [
                          DataColumn(label: Text('Buchungsdatum')),
                          DataColumn(label: Text('Buchungszeit')),
                          DataColumn(label: Text('Gebuchte Zeit')),
                          DataColumn(label: Text('Art')),
                          DataColumn(label: Text('Aufgabe')),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final booking in bookings)
                            DataRow(
                              cells: [
                                DataCell(Text(booking.bookingDate)),
                                DataCell(Text(booking.bookingTime)),
                                DataCell(Text(_durationLabel(booking
                                        .bookedMinutes +
                                    ((booking.trackedSeconds + 59) ~/ 60)))),
                                DataCell(Text(_sourceLabel(booking.source))),
                                DataCell(
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 360),
                                    child: Text(
                                      booking.taskText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Bearbeiten',
                                      onPressed: () => _editBooking(booking),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Löschen',
                                      onPressed: () => _deleteBooking(booking),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                )),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimeBookingDialog extends StatefulWidget {
  const _TimeBookingDialog({
    required this.booking,
    required this.taskOptions,
  });

  final TimeBooking? booking;
  final Map<String, String> taskOptions;

  @override
  State<_TimeBookingDialog> createState() => _TimeBookingDialogState();
}

class _TimeBookingDialogState extends State<_TimeBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late TimeOfDay _time;
  late String? _taskId;
  late final TextEditingController _durationController;

  @override
  void initState() {
    super.initState();
    final booking = widget.booking;
    final now = DateTime.now();
    _date = booking == null
        ? DateTime(now.year, now.month, now.day)
        : DateTime.tryParse(booking.bookingDate) ?? now;
    final timeParts = booking?.bookingTime.split(':') ?? const [];
    _time = timeParts.length == 2
        ? TimeOfDay(
            hour: int.tryParse(timeParts[0]) ?? now.hour,
            minute: int.tryParse(timeParts[1]) ?? now.minute,
          )
        : TimeOfDay.fromDateTime(now);
    _taskId = booking?.taskId ??
        (widget.taskOptions.isEmpty ? null : widget.taskOptions.keys.first);
    final bookedMinutes = (booking?.bookedMinutes ?? 0) +
        (((booking?.trackedSeconds ?? 0) + 59) ~/ 60);
    _durationController = TextEditingController(
      text: booking == null ? '' : '${bookedMinutes}m',
    );
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _chooseTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final taskId = _taskId;
    if (taskId == null) return;
    final duration = _parseDuration()!;
    final original = widget.booking;
    final previousMinutes = original == null
        ? null
        : original.bookedMinutes + ((original.trackedSeconds + 59) ~/ 60);
    final keepOriginalDuration =
        original != null && duration == previousMinutes;
    final booking = TimeBooking(
      id: widget.booking?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      bookingDate: DateFormat('yyyy-MM-dd').format(_date),
      bookingTime:
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      bookedMinutes: keepOriginalDuration
          ? original.bookedMinutes
          : _roundManualMinutes(duration),
      trackedSeconds: keepOriginalDuration ? original.trackedSeconds : 0,
      source: keepOriginalDuration ? original.source : 'manual',
      taskId: taskId,
      taskText: widget.taskOptions[taskId] ?? widget.booking?.taskText ?? '',
    );
    Navigator.pop(context, booking);
  }

  int? _parseDuration() {
    final match = RegExp(r'^([+-]?)(?:(\d+)\s*h(?:\s*(\d+)\s*m)?|(\d+)\s*m?)$')
        .firstMatch(_durationController.text.trim().toLowerCase());
    if (match == null) return null;
    final hours = int.tryParse(match.group(2) ?? '0');
    final minutes = int.tryParse(match.group(3) ?? match.group(4) ?? '0');
    if (hours == null || minutes == null) return null;
    final duration = hours * 60 + minutes;
    return match.group(1) == '-' ? -duration : duration;
  }

  int _roundManualMinutes(int duration) {
    final rounded = ((duration.abs() + 14) ~/ 15) * 15;
    return duration < 0 ? -rounded : rounded;
  }

  String? _validateDuration(String? value) {
    final duration = _parseDuration();
    if (duration == null) return 'Zahl mit optional m oder h eingeben';
    if (duration == 0) return 'Die Dauer darf nicht 0 sein';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final taskOptions = Map<String, String>.from(widget.taskOptions);
    final booking = widget.booking;
    final duration = _parseDuration();
    final originalMinutes = booking == null
        ? null
        : booking.bookedMinutes + ((booking.trackedSeconds + 59) ~/ 60);
    final rounded = duration == null ? null : _roundManualMinutes(duration);
    if (booking != null && !taskOptions.containsKey(booking.taskId)) {
      taskOptions[booking.taskId] = booking.taskText;
    }
    return AlertDialog(
      title: Text(booking == null ? 'Buchung erfassen' : 'Buchung bearbeiten'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _taskId,
                  decoration: const InputDecoration(labelText: 'Aufgabe'),
                  items: [
                    for (final entry in taskOptions.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: taskOptions.isEmpty
                      ? null
                      : (value) => setState(() => _taskId = value),
                  validator: (value) =>
                      value == null ? 'Aufgabe auswählen' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _chooseDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(DateFormat('dd.MM.yyyy').format(_date)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _chooseTime,
                        icon: const Icon(Icons.schedule),
                        label: Text(_time.format(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _durationController,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: 'Gebuchte Zeit',
                    hintText: '30m / 1h',
                    helperText: duration != null &&
                            duration != originalMinutes &&
                            duration != rounded
                        ? 'Buchung: $rounded min'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: _validateDuration,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}
