/// Validates that a date range is in the correct order.
///
/// Requirements:
/// - If both [start] and [end] are provided, [start] must not be after [end].
/// - If only one side is provided, the range is considered valid.
/// - Same-day ranges are allowed.
bool isValidDateRange(DateTime? start, DateTime? end) {
  if (start != null && end != null) {
    return !start.isAfter(end);
  }
  return true;
}
