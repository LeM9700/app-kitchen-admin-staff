import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/cards/stat_card.dart';
import 'package:app_admin_staff/design_system/components/feedback/app_feedback.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/admin_users/data/admin_users_repository.dart';
import 'package:app_admin_staff/features/hr/data/hr_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final hrWeekStartProvider = StateProvider<DateTime>((ref) {
  return _startOfWeek(DateTime.now());
});

final _hrEmployeeFilterProvider = StateProvider<int?>((ref) => null);
final _timeClockEmployeeFilterProvider = StateProvider<int?>((ref) => null);
final _timeClockStatusFilterProvider = StateProvider<String?>((ref) => null);
final _alertsResolvedFilterProvider = StateProvider<bool?>((ref) => null);
final _selectedHrAlertIdProvider = StateProvider<int?>((ref) => null);
final _clockActionLoadingProvider = StateProvider<bool>((ref) => false);

class HrAdminPage extends StatelessWidget {
  const HrAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.groups_2_outlined), text: 'Employes'),
                Tab(
                  icon: Icon(Icons.calendar_month_outlined),
                  text: 'Planning',
                ),
                Tab(icon: Icon(Icons.punch_clock_outlined), text: 'Pointages'),
                Tab(icon: Icon(Icons.warning_amber_outlined), text: 'Alertes'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _AdminEmployeesTab(),
                _AdminPlanningTab(),
                _AdminTimeClockTab(),
                _HrAlertsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StaffHrPage extends StatelessWidget {
  const StaffHrPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            child: TabBar(
              tabs: [
                Tab(
                  icon: Icon(Icons.calendar_today_outlined),
                  text: 'Planning',
                ),
                Tab(icon: Icon(Icons.timer_outlined), text: 'Activite'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _StaffScheduleTab(),
                _StaffActivityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminEmployeesTab extends ConsumerWidget {
  const _AdminEmployeesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(employeesProvider);
    final users =
        ref.watch(adminUsersProvider(const AdminUsersQuery(pageSize: 100)));
    final userMap = {
      for (final user in users.valueOrNull?.items ?? const <AdminUser>[])
        user.id: user,
    };

    return _ScreenPadding(
      child: employees.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.badge_outlined,
              title: 'Aucun profil RH',
            );
          }
          return ListView.separated(
            itemBuilder: (context, index) {
              final employee = items[index];
              return _EmployeeTile(
                employee: employee,
                user: userMap[employee.userId],
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: items.length,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorPanel(
          error: error,
          onRetry: () => ref.invalidate(employeesProvider),
        ),
      ),
    );
  }
}

class _EmployeeTile extends ConsumerWidget {
  const _EmployeeTile({
    required this.employee,
    required this.user,
  });

  final EmployeeProfile employee;
  final AdminUser? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hourly = employee.hourlyRateCents == null
        ? 'Non renseigne'
        : _currency(employee.hourlyRateCents! / 100);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CircleAvatar(child: Text(_avatarLabel(user?.displayName))),
            SizedBox(
              width: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? 'Employe #${employee.id}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(user?.email ?? 'Utilisateur #${employee.userId}'),
                ],
              ),
            ),
            _MetricChip(
              icon: Icons.storefront_outlined,
              label: 'Etab. ${employee.establishmentId}',
            ),
            _MetricChip(
              icon: Icons.schedule_outlined,
              label: '${employee.weeklyHoursContract}h/semaine',
            ),
            _MetricChip(icon: Icons.euro_outlined, label: hourly),
            Chip(
              avatar: Icon(
                employee.isActive
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
                size: 18,
              ),
              label: Text(employee.isActive ? 'Actif' : 'Inactif'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showEmployeeDialog(context, ref, employee),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifier'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPlanningTab extends ConsumerWidget {
  const _AdminPlanningTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(hrWeekStartProvider);
    final employeeFilter = ref.watch(_hrEmployeeFilterProvider);
    final weekEnd = weekStart.add(const Duration(days: 7));
    final shiftQuery = HrShiftQuery(
      employeeId: employeeFilter,
      dateFrom: weekStart,
      dateTo: weekEnd,
    );
    final employees = ref.watch(employeesProvider);
    final shifts = ref.watch(shiftsProvider(shiftQuery));
    final users =
        ref.watch(adminUsersProvider(const AdminUsersQuery(pageSize: 100)));
    final userMap = {
      for (final user in users.valueOrNull?.items ?? const <AdminUser>[])
        user.id: user,
    };
    final employeeItems = employees.valueOrNull ?? const <EmployeeProfile>[];
    final shiftItems = shifts.valueOrNull ?? const <HrShift>[];

    return _ScreenPadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Planning equipe',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      'Semaine du ${_weekRangeLabel(weekStart)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Semaine precedente',
                onPressed: () {
                  ref.read(hrWeekStartProvider.notifier).state =
                      weekStart.subtract(const Duration(days: 7));
                },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton.outlined(
                tooltip: 'Semaine suivante',
                onPressed: () {
                  ref.read(hrWeekStartProvider.notifier).state =
                      weekStart.add(const Duration(days: 7));
                },
                icon: const Icon(Icons.chevron_right),
              ),
              FilledButton.icon(
                onPressed: () => _showShiftDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Nouveau shift'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppStatCard(
                label: 'Membres',
                value: employeeItems.length.toString(),
                icon: Icons.groups_2_outlined,
                accentColor: AppColors.accent,
              ),
              AppStatCard(
                label: 'Shifts',
                value: shiftItems.length.toString(),
                icon: Icons.calendar_month_outlined,
                accentColor: AppColors.infoAlt,
              ),
              AppStatCard(
                label: 'Heures planifiees',
                value: '${_plannedHours(shiftItems).toStringAsFixed(1)}h',
                icon: Icons.schedule_outlined,
                accentColor: AppColors.success,
              ),
              AppStatCard(
                label: 'Conflits',
                value: _planningConflictCount(shiftItems).toString(),
                icon: Icons.warning_amber_outlined,
                accentColor: AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DsCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: employees.when(
              data: (items) => Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _EmployeeFilter(
                    employees: items,
                    users: userMap,
                    selectedEmployeeId: employeeFilter,
                    onChanged: (value) {
                      ref.read(_hrEmployeeFilterProvider.notifier).state =
                          value;
                    },
                  ),
                  const StatusBadge(
                    label: 'Vue semaine',
                    tone: StatusTone.neutral,
                    icon: Icons.view_week_outlined,
                  ),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => _InlineError(error: error),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: employees.when(
              data: (employeeItems) => shifts.when(
                data: (shiftItems) => _PlanningBoard(
                  employees: employeeFilter == null
                      ? employeeItems
                      : employeeItems
                          .where((item) => item.id == employeeFilter)
                          .toList(),
                  shifts: shiftItems,
                  weekStart: weekStart,
                  users: userMap,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => _ErrorPanel(
                  error: error,
                  onRetry: () => ref.invalidate(shiftsProvider(shiftQuery)),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorPanel(
                error: error,
                onRetry: () => ref.invalidate(employeesProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanningBoard extends StatelessWidget {
  const _PlanningBoard({
    required this.employees,
    required this.shifts,
    required this.weekStart,
    required this.users,
  });

  final List<EmployeeProfile> employees;
  final List<HrShift> shifts;
  final DateTime weekStart;
  final Map<int, AdminUser> users;

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_month_outlined,
        title: 'Aucun employe actif',
      );
    }
    final days =
        List.generate(7, (index) => weekStart.add(Duration(days: index)));
    final compact = Breakpoints.isCompactDesktop(context);
    if (compact || Breakpoints.isMobile(context)) {
      return ListView(
        children: [
          for (final day in days)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DayPlanningCard(
                day: day,
                employees: employees,
                shifts: shifts
                    .where((shift) => _sameDay(shift.startsAt, day))
                    .toList(),
                users: users,
              ),
            ),
        ],
      );
    }

    return DsCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1160),
          child: SingleChildScrollView(
            child: DataTable(
              columnSpacing: 14,
              headingRowHeight: 56,
              dataRowMinHeight: 92,
              dataRowMaxHeight: 132,
              columns: [
                const DataColumn(
                  label: SizedBox(width: 160, child: Text('Employe')),
                ),
                for (final day in days)
                  DataColumn(
                    label: SizedBox(
                      width: 126,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_weekdayFormat.format(day)),
                          Text(
                            day.day.toString(),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              rows: [
                for (final employee in employees)
                  DataRow(
                    cells: [
                      DataCell(Text(_employeeName(employee, users))),
                      for (final day in days)
                        DataCell(
                          SizedBox(
                            width: 126,
                            child: _ShiftStack(
                              shifts: shifts
                                  .where(
                                    (shift) =>
                                        shift.employeeId == employee.id &&
                                        _sameDay(shift.startsAt, day),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayPlanningCard extends StatelessWidget {
  const _DayPlanningCard({
    required this.day,
    required this.employees,
    required this.shifts,
    required this.users,
  });

  final DateTime day;
  final List<EmployeeProfile> employees;
  final List<HrShift> shifts;
  final Map<int, AdminUser> users;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _weekdayFormat.format(day),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            for (final employee in employees)
              _EmployeeDayLine(
                name: _employeeName(employee, users),
                shifts: shifts
                    .where((shift) => shift.employeeId == employee.id)
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeDayLine extends StatelessWidget {
  const _EmployeeDayLine({
    required this.name,
    required this.shifts,
  });

  final String name;
  final List<HrShift> shifts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          _ShiftStack(shifts: shifts),
        ],
      ),
    );
  }
}

class _ShiftStack extends StatelessWidget {
  const _ShiftStack({required this.shifts});

  final List<HrShift> shifts;

  @override
  Widget build(BuildContext context) {
    if (shifts.isEmpty) {
      return Text(
        '-',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final shift in shifts) _ShiftPill(shift: shift),
      ],
    );
  }
}

class _ShiftPill extends ConsumerWidget {
  const _ShiftPill({required this.shift});

  final HrShift shift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = shift.isCancelled
        ? StatusTone.danger
        : shift.startsAt.hour >= 15
            ? StatusTone.warning
            : StatusTone.info;
    final colors = StatusBadgeColors.fromTone(tone);
    return ActionChip(
      tooltip: shift.isCancelled ? 'Shift annule' : 'Modifier ce shift',
      backgroundColor: colors.background,
      side: BorderSide(color: colors.foreground.withValues(alpha: 0.28)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      label: Text(
        '${_timeFormat.format(shift.startsAt)}-${_timeFormat.format(shift.endsAt)}',
        style: TextStyle(
          color: colors.foreground,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      onPressed: () => _showShiftActions(context, ref, shift),
    );
  }
}

class _AdminTimeClockTab extends ConsumerWidget {
  const _AdminTimeClockTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeId = ref.watch(_timeClockEmployeeFilterProvider);
    final status = ref.watch(_timeClockStatusFilterProvider);
    final weekStart = ref.watch(hrWeekStartProvider);
    final query = TimeClockEntryQuery(
      employeeId: employeeId,
      status: status,
      dateFrom: weekStart,
      dateTo: weekStart.add(const Duration(days: 7)),
    );
    final entries = ref.watch(timeClockEntriesProvider(query));
    final employees = ref.watch(employeesProvider);
    final users =
        ref.watch(adminUsersProvider(const AdminUsersQuery(pageSize: 100)));
    final userMap = {
      for (final user in users.valueOrNull?.items ?? const <AdminUser>[])
        user.id: user,
    };
    final entryItems = entries.valueOrNull ?? const <TimeClockEntry>[];

    return _ScreenPadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pointages & corrections',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      'Entrees, sorties et corrections RH',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppStatCard(
                label: 'En service',
                value:
                    entryItems.where((entry) => entry.isOpen).length.toString(),
                icon: Icons.timer_outlined,
                accentColor: AppColors.success,
              ),
              AppStatCard(
                label: 'Anomalies',
                value: _timeClockAnomalyCount(entryItems).toString(),
                icon: Icons.warning_amber_outlined,
                accentColor: AppColors.danger,
              ),
              AppStatCard(
                label: 'Corrections semaine',
                value: entryItems
                    .where((entry) => entry.status == 'corrected')
                    .length
                    .toString(),
                icon: Icons.edit_calendar_outlined,
                accentColor: AppColors.warning,
              ),
              AppStatCard(
                label: 'Heures aujourd hui',
                value: '${_todayClockedHours(entryItems).toStringAsFixed(1)}h',
                icon: Icons.schedule_outlined,
                accentColor: AppColors.infoAlt,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DsCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: employees.when(
              data: (items) => Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _EmployeeFilter(
                    employees: items,
                    users: userMap,
                    selectedEmployeeId: employeeId,
                    onChanged: (value) {
                      ref
                          .read(_timeClockEmployeeFilterProvider.notifier)
                          .state = value;
                    },
                  ),
                  PillFilterBar<String>(
                    options: const [
                      PillFilterOption(value: 'all', label: 'Aujourd hui'),
                      PillFilterOption(value: 'open', label: 'En service'),
                      PillFilterOption(value: 'corrected', label: 'Corriges'),
                    ],
                    selected: status ?? 'all',
                    onSelected: (value) {
                      ref.read(_timeClockStatusFilterProvider.notifier).state =
                          value == 'all' ? null : value;
                    },
                  ),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => _InlineError(error: error),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: entries.when(
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.punch_clock_outlined,
                    title: 'Aucun pointage',
                  );
                }
                return ListView.separated(
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    final employee = _employeeById(
                      employees.valueOrNull ?? const [],
                      entry.employeeId,
                    );
                    return _TimeClockEntryTile(
                      entry: entry,
                      employeeName: employee == null
                          ? 'Employe #${entry.employeeId}'
                          : _employeeName(employee, userMap),
                      onCorrect: () =>
                          _showCorrectionDialog(context, ref, entry),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemCount: items.length,
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorPanel(
                error: error,
                onRetry: () => ref.invalidate(timeClockEntriesProvider(query)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffScheduleTab extends ConsumerWidget {
  const _StaffScheduleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(hrWeekStartProvider);
    final query = HrShiftQuery(
      dateFrom: weekStart,
      dateTo: weekStart.add(const Duration(days: 7)),
    );
    final shifts = ref.watch(myShiftsProvider(query));

    return _ScreenPadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Semaine du ${_dayFormat.format(weekStart)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton.outlined(
                tooltip: 'Semaine precedente',
                onPressed: () {
                  ref.read(hrWeekStartProvider.notifier).state =
                      weekStart.subtract(const Duration(days: 7));
                },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton.outlined(
                tooltip: 'Semaine suivante',
                onPressed: () {
                  ref.read(hrWeekStartProvider.notifier).state =
                      weekStart.add(const Duration(days: 7));
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: shifts.when(
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.calendar_today_outlined,
                    title: 'Aucun shift planifie',
                  );
                }
                return ListView.separated(
                  itemBuilder: (context, index) =>
                      _StaffShiftCard(shift: items[index]),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemCount: items.length,
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorPanel(
                error: error,
                onRetry: () => ref.invalidate(myShiftsProvider(query)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffActivityTab extends ConsumerWidget {
  const _StaffActivityTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineStatusProvider).valueOrNull ?? true;
    final loading = ref.watch(_clockActionLoadingProvider);
    final profile = ref.watch(myEmployeeProfileProvider);
    final weekStart = ref.watch(hrWeekStartProvider);
    final entriesQuery = TimeClockEntryQuery(
      dateFrom: weekStart,
      dateTo: weekStart.add(const Duration(days: 7)),
    );
    final entries = ref.watch(myTimeClockEntriesProvider(entriesQuery));
    final now = DateTime.now();
    final currentShiftQuery = HrShiftQuery(
      dateFrom: now.subtract(const Duration(hours: 8)),
      dateTo: now.add(const Duration(hours: 8)),
    );
    final shifts = ref.watch(myShiftsProvider(currentShiftQuery));

    return _ScreenPadding(
      child: profile.when(
        data: (profile) => entries.when(
          data: (items) {
            final openEntry = _openEntry(items);
            final currentShift = _currentShift(shifts.valueOrNull ?? const []);
            return ListView(
              children: [
                StaffDsCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          openEntry == null ? 'Hors service' : 'En service',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          online
                              ? 'Etablissement ${profile.establishmentId}'
                              : 'Offline',
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const ValueKey('staff-clock-action'),
                          onPressed: !online || loading
                              ? null
                              : () => _runClockAction(
                                    context,
                                    ref,
                                    openEntry: openEntry,
                                    profile: profile,
                                    shift: currentShift,
                                    query: entriesQuery,
                                  ),
                          icon: loading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  openEntry == null
                                      ? Icons.login_outlined
                                      : Icons.logout_outlined,
                                ),
                          label: Text(
                            openEntry == null
                                ? 'Pointer entree'
                                : 'Pointer sortie',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Historique',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const EmptyState(
                    icon: Icons.timer_outlined,
                    title: 'Aucun pointage',
                  )
                else
                  for (final entry in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TimeClockEntryTile(
                        entry: entry,
                        employeeName: 'Moi',
                      ),
                    ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _ErrorPanel(
            error: error,
            onRetry: () =>
                ref.invalidate(myTimeClockEntriesProvider(entriesQuery)),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorPanel(
          error: error,
          onRetry: () => ref.invalidate(myEmployeeProfileProvider),
        ),
      ),
    );
  }
}

class _HrAlertsTab extends ConsumerWidget {
  const _HrAlertsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref.watch(_alertsResolvedFilterProvider);
    final selectedAlertId = ref.watch(_selectedHrAlertIdProvider);
    final query = HrAlertsQuery(resolved: resolved);
    final alerts = ref.watch(hrAlertsProvider(query));
    final alertItems = alerts.valueOrNull ?? const <HrAlert>[];

    return _ScreenPadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alertes RH',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      'Anomalies detectees par le backend RH',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppStatCard(
                label: 'Critiques',
                value: alertItems
                    .where(
                      (alert) =>
                          alert.severity == 'critical' && !alert.isResolved,
                    )
                    .length
                    .toString(),
                icon: Icons.priority_high_outlined,
                accentColor: AppColors.danger,
              ),
              AppStatCard(
                label: 'A traiter',
                value: alertItems
                    .where((alert) => !alert.isResolved)
                    .length
                    .toString(),
                icon: Icons.warning_amber_outlined,
                accentColor: AppColors.warning,
              ),
              AppStatCard(
                label: 'Resolues 7j',
                value: alertItems
                    .where((alert) => alert.isResolved)
                    .length
                    .toString(),
                icon: Icons.check_circle_outline,
                accentColor: AppColors.success,
              ),
              const AppStatCard(
                label: 'Temps moyen',
                value: 'N/D',
                icon: Icons.hourglass_empty_outlined,
                accentColor: AppColors.neutral,
                subtitle: 'Non expose',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DsCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: PillFilterBar<String>(
              options: const [
                PillFilterOption(value: 'open', label: 'Ouvertes'),
                PillFilterOption(value: 'resolved', label: 'Resolues'),
                PillFilterOption(value: 'all', label: 'Toutes'),
              ],
              selected: resolved == null
                  ? 'all'
                  : resolved
                      ? 'resolved'
                      : 'open',
              onSelected: (selected) {
                ref.read(_alertsResolvedFilterProvider.notifier).state =
                    selected == 'all' ? null : selected == 'resolved';
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: alerts.when(
              data: (items) {
                if (items.isEmpty) {
                  return const AppFeedback(
                    kind: AppFeedbackKind.empty,
                    title: 'Aucune alerte RH',
                  );
                }
                HrAlert? selected;
                for (final alert in items) {
                  if (alert.id == selectedAlertId) {
                    selected = alert;
                    break;
                  }
                }
                final activeSelected = selected ?? items.first;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final current = ref.read(_selectedHrAlertIdProvider);
                  if (current != activeSelected.id) {
                    ref.read(_selectedHrAlertIdProvider.notifier).state =
                        activeSelected.id;
                  }
                });

                final list = ListView.separated(
                  itemBuilder: (context, index) => _HrAlertTile(
                    alert: items[index],
                    query: query,
                    selected: items[index].id == activeSelected.id,
                    onTap: () {
                      ref.read(_selectedHrAlertIdProvider.notifier).state =
                          items[index].id;
                    },
                  ),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemCount: items.length,
                );
                if (Breakpoints.isMobile(context) ||
                    Breakpoints.isCompactDesktop(context)) {
                  return ListView(
                    children: [
                      for (final alert in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _HrAlertTile(
                            alert: alert,
                            query: query,
                            selected: alert.id == activeSelected.id,
                            onTap: () {
                              ref
                                  .read(_selectedHrAlertIdProvider.notifier)
                                  .state = alert.id;
                            },
                          ),
                        ),
                      _HrAlertDetailCard(alert: activeSelected, query: query),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: list),
                    const SizedBox(width: AppSpacing.xl),
                    SizedBox(
                      width: 352,
                      child: _HrAlertDetailCard(
                        alert: activeSelected,
                        query: query,
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorPanel(
                error: error,
                onRetry: () => ref.invalidate(hrAlertsProvider(query)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HrAlertTile extends ConsumerWidget {
  const _HrAlertTile({
    required this.alert,
    required this.query,
    required this.selected,
    required this.onTap,
  });

  final HrAlert alert;
  final HrAlertsQuery query;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = _alertTone(alert);
    return DsCard(
      backgroundColor: selected ? AppColors.infoBg : null,
      borderColor: selected ? AppColors.infoAlt : null,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        minVerticalPadding: AppSpacing.sm,
        leading: Icon(
          Icons.warning_amber_outlined,
          color:
              tone == StatusTone.danger ? AppColors.danger : AppColors.warning,
        ),
        title: Text(_alertTitle(alert.type)),
        subtitle: Text(_alertSubtitle(alert)),
        trailing: alert.isResolved
            ? const StatusBadge(
                label: 'Resolue',
                tone: StatusTone.success,
                compact: true,
              )
            : OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await ref.read(hrRepositoryProvider).resolveAlert(alert.id);
                    ref.invalidate(hrAlertsProvider(query));
                  } catch (error) {
                    if (context.mounted) {
                      _showError(context, error);
                    }
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Resoudre'),
              ),
      ),
    );
  }
}

class _HrAlertDetailCard extends ConsumerWidget {
  const _HrAlertDetailCard({
    required this.alert,
    required this.query,
  });

  final HrAlert alert;
  final HrAlertsQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _alertTitle(alert.type),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StatusBadge(
                label: alert.isResolved ? 'Resolue' : alert.severity,
                tone: alert.isResolved ? StatusTone.success : _alertTone(alert),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _dateTimeFormat.format(alert.triggeredAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          DsCard(
            backgroundColor: AppColors.dangerBg,
            borderColor: const Color(0xFFF2C2C4),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              _alertSubtitle(alert),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (alert.payload.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Payload',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final entry in alert.payload.entries)
              _PayloadLine(label: entry.key, value: entry.value.toString()),
          ],
          const SizedBox(height: AppSpacing.md),
          if (!alert.isResolved)
            FilledButton.icon(
              onPressed: () async {
                try {
                  await ref.read(hrRepositoryProvider).resolveAlert(alert.id);
                  ref.invalidate(hrAlertsProvider(query));
                } catch (error) {
                  if (context.mounted) {
                    _showError(context, error);
                  }
                }
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Resoudre l alerte'),
            )
          else
            const StatusBadge(
              label: 'Resolution enregistree',
              tone: StatusTone.success,
              icon: Icons.check_circle_outline,
            ),
        ],
      ),
    );
  }
}

class _PayloadLine extends StatelessWidget {
  const _PayloadLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffShiftCard extends StatelessWidget {
  const _StaffShiftCard({required this.shift});

  final HrShift shift;

  @override
  Widget build(BuildContext context) {
    return StaffDsCard(
      child: ListTile(
        leading: Icon(
          shift.isCancelled ? Icons.event_busy_outlined : Icons.event_outlined,
          color: shift.isCancelled ? AppColors.danger : AppColors.info,
        ),
        title: Text(_weekdayFormat.format(shift.startsAt)),
        subtitle: Text(
          '${_timeFormat.format(shift.startsAt)} - ${_timeFormat.format(shift.endsAt)}'
          ' - pause ${shift.breakMinutes} min',
        ),
        trailing: StatusBadge(
          label: shift.status,
          tone: shift.isCancelled ? StatusTone.danger : StatusTone.info,
          compact: true,
        ),
      ),
    );
  }
}

class _TimeClockEntryTile extends StatelessWidget {
  const _TimeClockEntryTile({
    required this.entry,
    required this.employeeName,
    this.onCorrect,
  });

  final TimeClockEntry entry;
  final String employeeName;
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    final duration = _entryDurationLabel(entry);
    final status = StatusBadge(
      label: _timeClockStatusLabel(entry.status),
      tone: _timeClockStatusTone(entry),
      compact: true,
    );
    final correctionButton = onCorrect == null
        ? null
        : IconButton.outlined(
            tooltip: 'Corriger',
            onPressed: onCorrect,
            icon: const Icon(Icons.edit_calendar_outlined),
          );
    if (Breakpoints.isMobile(context)) {
      return DsCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  entry.isOpen ? Icons.timer_outlined : Icons.task_alt_outlined,
                  color: entry.isOpen ? AppColors.success : AppColors.neutral,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    employeeName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                status,
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Entree ${_dateTimeFormat.format(entry.clockInAt)}'),
            Text(
              entry.clockOutAt == null
                  ? 'Sortie en cours'
                  : 'Sortie ${_dateTimeFormat.format(entry.clockOutAt!)}',
            ),
            Text('Duree $duration'),
            if (correctionButton != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(alignment: Alignment.centerRight, child: correctionButton),
            ],
          ],
        ),
      );
    }
    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(
            entry.isOpen ? Icons.timer_outlined : Icons.task_alt_outlined,
            color: entry.isOpen ? AppColors.success : AppColors.neutral,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employeeName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Entree ${_dateTimeFormat.format(entry.clockInAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              entry.clockOutAt == null
                  ? 'Sortie en cours'
                  : 'Sortie ${_dateTimeFormat.format(entry.clockOutAt!)}',
            ),
          ),
          Expanded(child: Text(duration)),
          status,
          if (correctionButton != null) ...[
            const SizedBox(width: AppSpacing.xs),
            correctionButton,
          ],
        ],
      ),
    );
  }
}

class _EmployeeFilter extends StatelessWidget {
  const _EmployeeFilter({
    required this.employees,
    required this.users,
    required this.selectedEmployeeId,
    required this.onChanged,
  });

  final List<EmployeeProfile> employees;
  final Map<int, AdminUser> users;
  final int? selectedEmployeeId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<int>(
      width: 260,
      initialSelection: selectedEmployeeId ?? 0,
      label: const Text('Employe'),
      dropdownMenuEntries: [
        const DropdownMenuEntry(value: 0, label: 'Tous'),
        for (final employee in employees)
          DropdownMenuEntry(
            value: employee.id,
            label: _employeeName(employee, users),
          ),
      ],
      onSelected: (value) => onChanged(value == 0 ? null : value),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _ScreenPadding extends StatelessWidget {
  const _ScreenPadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final horizontal =
        Breakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl;
    return Padding(
      padding: EdgeInsets.all(horizontal),
      child: child,
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(_errorMessage(error), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Text(
      _errorMessage(error),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

Future<void> _showEmployeeDialog(
  BuildContext context,
  WidgetRef ref,
  EmployeeProfile employee,
) async {
  final establishmentController =
      TextEditingController(text: employee.establishmentId.toString());
  final rateController = TextEditingController(
    text: employee.hourlyRateCents == null
        ? ''
        : (employee.hourlyRateCents! / 100).toStringAsFixed(2),
  );
  final hoursController =
      TextEditingController(text: employee.weeklyHoursContract.toString());
  var isActive = employee.isActive;

  final result = await showDialog<EmployeeProfileUpdateDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Profil RH #${employee.id}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: establishmentController,
                decoration: const InputDecoration(labelText: 'Etablissement'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rateController,
                decoration:
                    const InputDecoration(labelText: 'Taux horaire EUR'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hoursController,
                decoration: const InputDecoration(labelText: 'Heures contrat'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: isActive,
                onChanged: (value) => setState(() => isActive = value),
                title: const Text('Actif'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () {
              final rate =
                  double.tryParse(rateController.text.replaceAll(',', '.'));
              Navigator.of(context).pop(
                EmployeeProfileUpdateDraft(
                  establishmentId: int.tryParse(establishmentController.text),
                  hourlyRateCents: rate == null ? null : (rate * 100).round(),
                  weeklyHoursContract: int.tryParse(hoursController.text),
                  isActive: isActive,
                ),
              );
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );

  establishmentController.dispose();
  rateController.dispose();
  hoursController.dispose();

  if (result == null) {
    return;
  }
  try {
    await ref.read(hrRepositoryProvider).updateEmployee(employee.id, result);
    ref.invalidate(employeesProvider);
  } catch (error) {
    if (context.mounted) {
      _showError(context, error);
    }
  }
}

Future<void> _showShiftDialog(
  BuildContext context,
  WidgetRef ref, {
  HrShift? shift,
}) async {
  final employees = await ref.read(employeesProvider.future);
  if (!context.mounted) {
    return;
  }
  if (employees.isEmpty) {
    _showError(
      context,
      const HrValidationException('Aucun employe disponible'),
    );
    return;
  }
  final initialEmployeeId = shift?.employeeId ?? employees.first.id;
  final initialEstablishmentId =
      shift?.establishmentId ?? employees.first.establishmentId;
  var employeeId = initialEmployeeId;
  final establishmentController =
      TextEditingController(text: initialEstablishmentId.toString());
  final startsController = TextEditingController(
    text: _inputDateFormat.format(shift?.startsAt ?? DateTime.now()),
  );
  final endsController = TextEditingController(
    text: _inputDateFormat.format(
      shift?.endsAt ?? DateTime.now().add(const Duration(hours: 4)),
    ),
  );
  final breakController =
      TextEditingController(text: (shift?.breakMinutes ?? 0).toString());
  String? localError;

  final result = await showDialog<ShiftDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(shift == null ? 'Ajouter un shift' : 'Modifier le shift'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: employeeId,
                decoration: const InputDecoration(labelText: 'Employe'),
                items: [
                  for (final employee in employees)
                    DropdownMenuItem(
                      value: employee.id,
                      child: Text('Employe #${employee.id}'),
                    ),
                ],
                onChanged: shift == null
                    ? (value) {
                        if (value == null) {
                          return;
                        }
                        final selected = employees.firstWhere(
                          (employee) => employee.id == value,
                        );
                        setState(() {
                          employeeId = value;
                          establishmentController.text =
                              selected.establishmentId.toString();
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: establishmentController,
                enabled: shift == null,
                decoration: const InputDecoration(labelText: 'Etablissement'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('shift-starts-at'),
                controller: startsController,
                decoration:
                    const InputDecoration(labelText: 'Debut yyyy-MM-dd HH:mm'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('shift-ends-at'),
                controller: endsController,
                decoration:
                    const InputDecoration(labelText: 'Fin yyyy-MM-dd HH:mm'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: breakController,
                decoration: const InputDecoration(labelText: 'Pause minutes'),
                keyboardType: TextInputType.number,
              ),
              if (localError != null) ...[
                const SizedBox(height: 12),
                Text(
                  localError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () {
              final startsAt = _parseInputDateTime(startsController.text);
              final endsAt = _parseInputDateTime(endsController.text);
              final establishmentId =
                  int.tryParse(establishmentController.text) ?? 0;
              final breakMinutes = int.tryParse(breakController.text) ?? -1;
              if (startsAt == null || endsAt == null) {
                setState(() => localError = 'Date invalide');
                return;
              }
              final draft = ShiftDraft(
                employeeId: employeeId,
                establishmentId: establishmentId,
                startsAt: startsAt,
                endsAt: endsAt,
                breakMinutes: breakMinutes,
                status: shift?.status,
              );
              final error = draft.validate();
              if (error != null) {
                setState(() => localError = error);
                return;
              }
              Navigator.of(context).pop(draft);
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );

  establishmentController.dispose();
  startsController.dispose();
  endsController.dispose();
  breakController.dispose();

  if (result == null) {
    return;
  }
  try {
    if (shift == null) {
      await ref.read(hrRepositoryProvider).createShift(result);
    } else {
      await ref.read(hrRepositoryProvider).updateShift(shift.id, result);
    }
    ref.invalidate(shiftsProvider);
    ref.invalidate(myShiftsProvider);
  } catch (error) {
    if (context.mounted) {
      _showError(context, error);
    }
  }
}

Future<void> _showShiftActions(
  BuildContext context,
  WidgetRef ref,
  HrShift shift,
) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          runSpacing: 8,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Modifier'),
              onTap: () {
                Navigator.of(context).pop();
                _showShiftDialog(context, ref, shift: shift);
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('Annuler le shift'),
              enabled: !shift.isCancelled,
              onTap: () async {
                Navigator.of(context).pop();
                final confirmed = await _confirm(
                  context,
                  title: 'Annuler le shift',
                  content:
                      'Le shift restera dans le planning en statut cancelled.',
                );
                if (!context.mounted) {
                  return;
                }
                if (!confirmed) {
                  return;
                }
                try {
                  await ref.read(hrRepositoryProvider).cancelShift(shift.id);
                  ref.invalidate(shiftsProvider);
                  ref.invalidate(myShiftsProvider);
                } catch (error) {
                  if (context.mounted) {
                    _showError(context, error);
                  }
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showCorrectionDialog(
  BuildContext context,
  WidgetRef ref,
  TimeClockEntry entry,
) async {
  final inController =
      TextEditingController(text: _inputDateFormat.format(entry.clockInAt));
  final outController = TextEditingController(
    text: entry.clockOutAt == null
        ? ''
        : _inputDateFormat.format(entry.clockOutAt!),
  );
  final reasonController = TextEditingController();
  String? localError;

  final result = await showDialog<TimeClockCorrectionDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Corriger le pointage'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: inController,
                decoration:
                    const InputDecoration(labelText: 'Entree yyyy-MM-dd HH:mm'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: outController,
                decoration:
                    const InputDecoration(labelText: 'Sortie yyyy-MM-dd HH:mm'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('timeclock-correction-reason'),
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Motif'),
              ),
              if (localError != null) ...[
                const SizedBox(height: 12),
                Text(
                  localError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () {
              final reason = reasonController.text.trim();
              final clockIn = _parseInputDateTime(inController.text);
              final clockOut = outController.text.trim().isEmpty
                  ? null
                  : _parseInputDateTime(outController.text);
              if (reason.isEmpty || clockIn == null) {
                setState(() => localError = 'Motif et entree requis');
                return;
              }
              if (outController.text.trim().isNotEmpty && clockOut == null) {
                setState(() => localError = 'Date de sortie invalide');
                return;
              }
              Navigator.of(context).pop(
                TimeClockCorrectionDraft(
                  newClockInAt: clockIn,
                  newClockOutAt: clockOut,
                  reason: reason,
                ),
              );
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Corriger'),
          ),
        ],
      ),
    ),
  );

  inController.dispose();
  outController.dispose();
  reasonController.dispose();

  if (result == null) {
    return;
  }
  try {
    await ref
        .read(hrRepositoryProvider)
        .correctTimeClockEntry(entry.id, result);
    ref.invalidate(timeClockEntriesProvider);
    ref.invalidate(myTimeClockEntriesProvider);
  } catch (error) {
    if (context.mounted) {
      _showError(context, error);
    }
  }
}

Future<void> _runClockAction(
  BuildContext context,
  WidgetRef ref, {
  required TimeClockEntry? openEntry,
  required EmployeeProfileSelf profile,
  required HrShift? shift,
  required TimeClockEntryQuery query,
}) async {
  ref.read(_clockActionLoadingProvider.notifier).state = true;
  try {
    if (openEntry == null) {
      await ref.read(hrRepositoryProvider).clockIn(
            ClockInDraft(
              method: 'web',
              establishmentId: profile.establishmentId,
              shiftId: shift?.id,
            ),
          );
    } else {
      await ref.read(hrRepositoryProvider).clockOut();
    }
    ref.invalidate(myTimeClockEntriesProvider(query));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(openEntry == null ? 'Pointage demarre' : 'Pointage termine'),
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      _showError(context, error);
    }
  } finally {
    ref.read(_clockActionLoadingProvider.notifier).state = false;
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Non'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Oui'),
            ),
          ],
        ),
      ) ??
      false;
}

void _showError(BuildContext context, Object error) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_errorMessage(error))),
  );
}

String _employeeName(EmployeeProfile employee, Map<int, AdminUser> users) {
  return users[employee.userId]?.displayName ?? 'Employe #${employee.id}';
}

String _weekRangeLabel(DateTime weekStart) {
  final weekEnd = weekStart.add(const Duration(days: 6));
  return '${_dayFormat.format(weekStart)} au ${_dayFormat.format(weekEnd)}';
}

double _plannedHours(List<HrShift> shifts) {
  var minutes = 0;
  for (final shift in shifts) {
    if (shift.isCancelled) {
      continue;
    }
    minutes += shift.endsAt.difference(shift.startsAt).inMinutes;
    minutes -= shift.breakMinutes;
  }
  return minutes <= 0 ? 0 : minutes / 60;
}

int _planningConflictCount(List<HrShift> shifts) {
  var conflicts = 0;
  for (var i = 0; i < shifts.length; i++) {
    final current = shifts[i];
    if (current.isCancelled) {
      continue;
    }
    for (var j = i + 1; j < shifts.length; j++) {
      final other = shifts[j];
      if (other.isCancelled || other.employeeId != current.employeeId) {
        continue;
      }
      final overlaps = current.startsAt.isBefore(other.endsAt) &&
          other.startsAt.isBefore(current.endsAt);
      if (overlaps) {
        conflicts++;
      }
    }
  }
  return conflicts;
}

int _timeClockAnomalyCount(List<TimeClockEntry> entries) {
  const expected = {'open', 'closed', 'corrected'};
  return entries.where((entry) => !expected.contains(entry.status)).length;
}

double _todayClockedHours(List<TimeClockEntry> entries) {
  final now = DateTime.now();
  var minutes = 0;
  for (final entry in entries) {
    if (!_sameDay(entry.clockInAt, now) || entry.clockOutAt == null) {
      continue;
    }
    minutes += entry.clockOutAt!.difference(entry.clockInAt).inMinutes;
  }
  return minutes <= 0 ? 0 : minutes / 60;
}

String _entryDurationLabel(TimeClockEntry entry) {
  final out = entry.clockOutAt;
  if (out == null) {
    return 'En cours';
  }
  final minutes = out.difference(entry.clockInAt).inMinutes;
  final hours = minutes ~/ 60;
  final rest = minutes.remainder(60).abs();
  return '${hours}h${rest.toString().padLeft(2, '0')}';
}

String _timeClockStatusLabel(String status) {
  return switch (status) {
    'open' => 'En service',
    'closed' => 'Termine',
    'corrected' => 'Corrige',
    _ => status,
  };
}

StatusTone _timeClockStatusTone(TimeClockEntry entry) {
  if (entry.status == 'open') {
    return StatusTone.success;
  }
  if (entry.status == 'corrected') {
    return StatusTone.warning;
  }
  if (entry.status == 'closed') {
    return StatusTone.neutral;
  }
  return StatusTone.danger;
}

StatusTone _alertTone(HrAlert alert) {
  if (alert.isResolved) {
    return StatusTone.success;
  }
  return alert.severity == 'critical' ? StatusTone.danger : StatusTone.warning;
}

TimeClockEntry? _openEntry(List<TimeClockEntry> entries) {
  for (final entry in entries) {
    if (entry.isOpen) {
      return entry;
    }
  }
  return null;
}

EmployeeProfile? _employeeById(List<EmployeeProfile> employees, int id) {
  for (final employee in employees) {
    if (employee.id == id) {
      return employee;
    }
  }
  return null;
}

HrShift? _currentShift(List<HrShift> shifts) {
  final now = DateTime.now();
  for (final shift in shifts) {
    if (shift.isCancelled) {
      continue;
    }
    if (now.isAfter(shift.startsAt.subtract(const Duration(minutes: 30))) &&
        now.isBefore(shift.endsAt.add(const Duration(minutes: 30)))) {
      return shift;
    }
  }
  return null;
}

String _avatarLabel(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return '#';
  }
  return raw.characters.first.toUpperCase();
}

String _alertTitle(String type) {
  switch (type) {
    case 'late':
      return 'Retard';
    case 'shift_overrun':
      return 'Depassement de shift';
    case 'weekly_overtime':
      return 'Heures hebdomadaires';
    case 'labor_cost_risk':
      return 'Risque cout main d oeuvre';
  }
  return type;
}

String _alertSubtitle(HrAlert alert) {
  final parts = <String>[
    if (alert.employeeId != null) 'Employe #${alert.employeeId}',
    if (alert.establishmentId != null) 'Etab. ${alert.establishmentId}',
    _dateTimeFormat.format(alert.triggeredAt),
  ];
  for (final entry in alert.payload.entries) {
    parts.add('${entry.key}: ${entry.value}');
  }
  return parts.join(' - ');
}

String _errorMessage(Object error) {
  if (error is HrValidationException) {
    return error.message;
  }
  if (error is AppException) {
    if (error.statusCode == 403) {
      return 'Acces refuse';
    }
    if (error.statusCode == 404) {
      return 'Element introuvable';
    }
    return error.message;
  }
  return error.toString();
}

DateTime _startOfWeek(DateTime value) {
  final local = DateTime(value.year, value.month, value.day);
  return local.subtract(Duration(days: local.weekday - 1));
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime? _parseInputDateTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  try {
    return _inputDateFormat.parseStrict(value);
  } catch (_) {
    return DateTime.tryParse(value);
  }
}

String _currency(double value) {
  return '${value.toStringAsFixed(2)} EUR';
}

final _dayFormat = DateFormat('dd/MM');
final _weekdayFormat = DateFormat('EEE dd/MM');
final _timeFormat = DateFormat('HH:mm');
final _dateTimeFormat = DateFormat('dd/MM HH:mm');
final _inputDateFormat = DateFormat('yyyy-MM-dd HH:mm');
