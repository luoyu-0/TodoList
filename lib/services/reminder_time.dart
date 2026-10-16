DateTime defaultReminderAt(DateTime dueAt, bool dueHasTime) {
  if (dueHasTime) return dueAt;
  return DateTime(dueAt.year, dueAt.month, dueAt.day, 9);
}

DateTime? effectiveReminderAt(
  DateTime? dueAt,
  bool dueHasTime,
  DateTime? reminderAt,
) {
  if (dueAt == null) return null;
  return reminderAt ?? defaultReminderAt(dueAt, dueHasTime);
}

DateTime? with24HourTime(DateTime date, String input) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(input.trim());
  if (match == null) return null;
  return DateTime(
    date.year,
    date.month,
    date.day,
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
  );
}
