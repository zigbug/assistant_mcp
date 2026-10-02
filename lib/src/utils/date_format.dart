// Форматирование дат, которые бэкенд отдаёт в виде epoch-миллисекунд.
//
// Без этих хелперов модель видит «1790899200000» вместо даты и не может
// ни сравнить сроки, ни показать человеку читаемое время.

/// Приводит значение даты к ISO-строке UTC.
///
/// Принимает и epoch-миллисекунды (`int`, как их отдаёт Drift), и уже
/// готовые ISO-строки — формат ответа может отличаться от запроса.
String? isoOf(Object? raw) {
  if (raw == null) return null;
  if (raw is String) return raw;
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(
      raw,
      isUtc: true,
    ).toIso8601String();
  }
  if (raw is double) {
    return DateTime.fromMillisecondsSinceEpoch(
      raw.toInt(),
      isUtc: true,
    ).toIso8601String();
  }
  return raw.toString();
}

/// Читаемый интервал `начало — окончание`. Если окончания нет, одиночное время.
String formatRange(Object? start, Object? end) {
  final from = isoOf(start);
  final to = isoOf(end);
  if (from == null) return 'время не назначено';
  if (to == null) return from;
  return '$from — $to';
}

/// Дата без времени: `2026-10-02`.
String? dateOnly(Object? raw) {
  final iso = isoOf(raw);
  if (iso == null) return null;
  return iso.length >= 10 ? iso.substring(0, 10) : iso;
}

/// Календарная дата поля «без времени» в локальной зоне: `02.10.2026`.
///
/// Бэкенд хранит date-only поля (план на дату, `scheduledDate`,
/// `repeatEndDate`) как локальную полночь, конвертированную в UTC. Поэтому
/// обрезка по UTC уехала бы на день назад: план на 02.10 лежит в epoch
/// `2026-10-01T21:00Z` для Europe/Moscow.
String humanLocalDate(Object? raw) {
  if (raw == null) return '—';
  if (raw is int) {
    return _formatLocal(DateTime.fromMillisecondsSinceEpoch(raw));
  }
  if (raw is double) {
    return _formatLocal(DateTime.fromMillisecondsSinceEpoch(raw.toInt()));
  }
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return _formatLocal(parsed.toLocal());
  }
  return raw.toString();
}

/// Локальная дата ISO для агрегированных сводок: `2026-10-02`.
String localDateOnly(Object? raw) {
  if (raw == null) return '—';
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(
      raw,
    ).toIso8601String().substring(0, 10);
  }
  if (raw is double) {
    return DateTime.fromMillisecondsSinceEpoch(
      raw.toInt(),
    ).toIso8601String().substring(0, 10);
  }
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return parsed.toLocal().toIso8601String().substring(0, 10);
  }
  return raw.toString();
}

String _formatLocal(DateTime local) {
  final iso = local.toIso8601String();
  return '${iso.substring(8, 10)}.${iso.substring(5, 7)}'
      '.${iso.substring(0, 4)}';
}

/// Читаемое представление даты для списков задач: `02.10.2026`.
String humanDate(Object? raw) {
  final iso = isoOf(raw);
  if (iso == null) return '—';
  if (iso.length < 10) return iso;
  return '${iso.substring(8, 10)}.${iso.substring(5, 7)}'
      '.${iso.substring(0, 4)}';
}
