class ImportPreview {
  const ImportPreview({
    required this.visitsTotal,
    required this.valid,
    required this.skipped,
    required this.inserts,
    required this.updates,
    required this.tagsToCreate,
    required this.errorCount,
    required this.warningCount,
  });

  final int visitsTotal;
  final int valid;
  final int skipped;
  final int inserts;
  final int updates;
  final int tagsToCreate;
  final int errorCount;
  final int warningCount;
}
