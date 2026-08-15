import 'package:app_admin_staff/features/hr/data/hr_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void invalidateHrProviders(WidgetRef ref) {
  ref
    ..invalidate(employeesProvider)
    ..invalidate(myEmployeeProfileProvider)
    ..invalidate(shiftsProvider)
    ..invalidate(myShiftsProvider)
    ..invalidate(timeClockEntriesProvider)
    ..invalidate(myTimeClockEntriesProvider)
    ..invalidate(hrAlertsProvider);
}
