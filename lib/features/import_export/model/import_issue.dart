enum ImportIssueSeverity { error, warning, info }

class ImportIssue {
  const ImportIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.location,
    this.context,
  });

  final ImportIssueSeverity severity;
  final String code;
  final String message;
  final String? location;
  final Map<String, Object?>? context;
}
