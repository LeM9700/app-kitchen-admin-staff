import 'package:app_admin_staff/core/printing/print_job.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final printJobsProvider = NotifierProvider<PrintJobQueue, List<PrintJob>>(
  PrintJobQueue.new,
);

class PrintJobQueue extends Notifier<List<PrintJob>> {
  @override
  List<PrintJob> build() => const [];

  void enqueue(PrintJob job) {
    state = [job, ...state.take(24)];
  }

  void markDone(String id) {
    state = state.where((job) => job.id != id).toList();
  }
}
