class ExportPayload {
  const ExportPayload({
    required this.format,
    required this.version,
    required this.exportedAt,
    required this.tags,
    required this.visits,
  });

  final String format;
  final int version;
  final String exportedAt;
  final List<ExportTag> tags;
  final List<ExportVisit> visits;

  Map<String, Object?> toJson() {
    return {
      'format': format,
      'version': version,
      'exported_at': exportedAt,
      'tags': tags.map((t) => t.toJson()).toList(),
      'visits': visits.map((v) => v.toJson()).toList(),
    };
  }
}

class ExportTag {
  const ExportTag({
    required this.tagId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String tagId;
  final String name;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toJson() {
    return {
      'tag_id': tagId,
      'name': name,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class ExportVisit {
  const ExportVisit({
    required this.visitId,
    required this.placeCode,
    required this.title,
    required this.level,
    this.startDate,
    this.endDate,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.tagIds,
  });

  final String visitId;
  final String placeCode;
  final String title;
  final int level;
  final String? startDate;
  final String? endDate;
  final String? note;
  final int createdAt;
  final int updatedAt;
  final List<String> tagIds;

  Map<String, Object?> toJson() {
    return {
      'visit_id': visitId,
      'place_code': placeCode,
      'title': title,
      'start_date': startDate,
      'end_date': endDate,
      'level': level,
      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'tag_ids': tagIds,
    };
  }
}
