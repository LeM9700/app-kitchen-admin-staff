class PrintJob {
  const PrintJob({
    required this.id,
    required this.kind,
    required this.title,
    required this.content,
    required this.createdAt,
    this.station,
  });

  final String id;
  final String kind;
  final String title;
  final String content;
  final DateTime createdAt;
  final String? station;
}
