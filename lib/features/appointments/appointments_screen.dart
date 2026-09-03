import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/models/appointment_models.dart';
import '../../core/providers/appointment_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  AppointmentStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAppointments());
  }

  Future<void> _loadAppointments() async {
    await context.read<AppointmentProvider>().loadAppointments(
          date: _selectedDate,
          status: _statusFilter,
        );
    if (mounted) {
      await context.read<AppointmentProvider>().loadUpcomingAppointments();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _selectedDate = DateTime(picked.year, picked.month, picked.day));
    await _loadAppointments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Appointments')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/appointment/new');
          if (mounted) await _loadAppointments();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Appointment'),
      ),
      body: Consumer<AppointmentProvider>(
        builder: (context, provider, _) {
          final grouped = <String, List<Appointment>>{};
          for (final appointment in provider.appointments) {
            grouped.putIfAbsent(appointment.startTime, () => []).add(appointment);
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _loadAppointments,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _DateFilterCard(
                  selectedDate: _selectedDate,
                  onPrevious: () async {
                    setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
                    await _loadAppointments();
                  },
                  onNext: () async {
                    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                    await _loadAppointments();
                  },
                  onPickDate: _pickDate,
                ),
                const SizedBox(height: 12),
                _StatusFilterChips(
                  value: _statusFilter,
                  onChanged: (status) async {
                    setState(() => _statusFilter = status);
                    await _loadAppointments();
                  },
                ),
                const SizedBox(height: 16),
                if (provider.isLoading)
                  const LinearProgressIndicator(color: AppColors.primary)
                else if (grouped.isEmpty)
                  const SizedBox(
                    height: 360,
                    child: EmptyState(
                      title: 'No appointments',
                      subtitle: 'Schedule an appointment for this day to see it here.',
                      icon: Icons.event_busy_rounded,
                    ),
                  )
                else
                  ...grouped.entries.map((entry) => _TimeGroup(
                        time: entry.key,
                        appointments: entry.value,
                        onActionComplete: _loadAppointments,
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DateFilterCard extends StatelessWidget {
  final DateTime selectedDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickDate;

  const _DateFilterCard({
    required this.selectedDate,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(selectedDate, DateTime.now());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: InkWell(
              onTap: onPickDate,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      isToday ? 'Today' : AppFormatters.formatDayMonth(selectedDate),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textHint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppFormatters.formatDate(selectedDate),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterChips extends StatelessWidget {
  final AppointmentStatus? value;
  final ValueChanged<AppointmentStatus?> onChanged;

  const _StatusFilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = <AppointmentStatus?>[
      null,
      AppointmentStatus.pending,
      AppointmentStatus.completed,
      AppointmentStatus.notAttended,
      AppointmentStatus.cancelled,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((status) {
          final selected = value == status;
          final label = status == null ? 'All' : status.label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => onChanged(status),
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              selectedColor: AppColors.primary,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selected ? AppColors.primary : AppColors.divider,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TimeGroup extends StatelessWidget {
  final String time;
  final List<Appointment> appointments;
  final Future<void> Function() onActionComplete;

  const _TimeGroup({
    required this.time,
    required this.appointments,
    required this.onActionComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          ...appointments.map((appointment) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AppointmentCard(
                  appointment: appointment,
                  onActionComplete: onActionComplete,
                ),
              )),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final Future<void> Function() onActionComplete;

  const _AppointmentCard({
    required this.appointment,
    required this.onActionComplete,
  });

  bool get _canEdit => appointment.status == AppointmentStatus.pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appointment.customerName ?? 'Customer #${appointment.customerId}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    AppointmentStatusBadge(status: appointment.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  appointment.serviceNameSnapshot,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  appointment.endTime == null
                      ? appointment.startTime
                      : '${appointment.startTime} - ${appointment.endTime}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                ),
                if ((appointment.customerPhone ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    appointment.customerPhone!,
                    style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                ],
                if ((appointment.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    appointment.notes!.trim(),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (_canEdit)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textHint),
              onSelected: (value) => _handleAction(context, value),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'complete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.check_circle_rounded),
                    title: Text('Mark Completed'),
                  ),
                ),
                PopupMenuItem(
                  value: 'notAttended',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.person_off_rounded),
                    title: Text('Mark Not Attended'),
                  ),
                ),
                PopupMenuItem(
                  value: 'cancel',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.event_busy_rounded),
                    title: Text('Cancel Appointment'),
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.edit_rounded),
                    title: Text('Edit'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('Delete'),
                  ),
                ),
              ],
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, String value) async {
    final provider = context.read<AppointmentProvider>();
    try {
      if (value == 'edit') {
        await context.push('/appointment/${appointment.id}/edit');
      } else if (value == 'complete') {
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Mark appointment completed?',
          message: 'This will create a visit linked to the appointment.',
          confirmLabel: 'Mark Completed',
          confirmColor: AppColors.success,
        );
        if (!confirmed) return;
        final visitId = await provider.markCompleted(appointment);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Appointment completed. Visit #$visitId created.')),
          );
        }
      } else if (value == 'notAttended') {
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Mark not attended?',
          message: 'This appointment will be marked as not attended.',
          confirmLabel: 'Mark Not Attended',
          confirmColor: AppColors.warning,
        );
        if (!confirmed) return;
        await provider.markNotAttended(appointment.id!);
      } else if (value == 'cancel') {
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Cancel appointment?',
          message: 'This appointment will be marked as cancelled.',
          confirmLabel: 'Cancel Appointment',
          confirmColor: AppColors.error,
        );
        if (!confirmed) return;
        await provider.cancelAppointment(appointment.id!);
      } else if (value == 'delete') {
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Delete appointment?',
          message: 'This only works for appointments not linked to a visit.',
          confirmLabel: 'Delete',
          confirmColor: AppColors.error,
        );
        if (!confirmed) return;
        await provider.deleteAppointment(appointment.id!);
      }
      await onActionComplete();
    } on InUseException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update appointment: $e')),
        );
      }
    }
  }
}
