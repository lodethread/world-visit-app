import 'package:flutter_test/flutter_test.dart';
import 'package:world_visit_app/util/date_validation.dart';

void main() {
  group('isValidDateRange', () {
    test('allows null boundaries', () {
      expect(isValidDateRange(null, null), isTrue);
      expect(isValidDateRange(DateTime(2024, 1, 1), null), isTrue);
      expect(isValidDateRange(null, DateTime(2024, 1, 1)), isTrue);
    });

    test('allows same day ranges', () {
      final date = DateTime(2024, 2, 2);
      expect(isValidDateRange(date, date), isTrue);
    });

    test('enforces start before or equal to end', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 1, 2);
      final invalidEnd = DateTime(2023, 12, 31);

      expect(isValidDateRange(start, end), isTrue);
      expect(isValidDateRange(start, invalidEnd), isFalse);
    });
  });
}
