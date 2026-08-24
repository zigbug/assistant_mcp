// Утилиты для удобного формирования query-параметров и JSON-тела запроса.
//
// Убирает boilerplate-код вида:
// ```dart
// if (args['status'] != null) {
//   queryParams['status'] = args['status'].toString();
// }
// ```
//
// Заменяя его на декларативный:
// ```dart
// queryParams.addIfPresent('status', args['status']);
// ```

/// Расширение для удобного добавления query-параметров.
///
/// Query-параметры — это всегда `Map<String, String>`, где значения
/// приводятся к строке для URL-кодирования.
extension QueryParamsExtension on Map<String, String> {
  /// Добавляет значение в мапу, если оно не null.
  ///
  /// Значение приводится к строке через `.toString()`.
  ///
  /// Пример:
  /// ```dart
  /// final params = <String, String>{};
  /// params.addIfPresent('status', 'todo');    // добавит
  /// params.addIfPresent('project_id', null);  // не добавит
  /// ```
  void addIfPresent(String key, Object? value) {
    if (value != null) {
      this[key] = value.toString();
    }
  }

  /// Добавляет булево значение как 'true', только если оно равно `true`.
  ///
  /// Это типичный паттерн для query-параметров: отсутствие параметра
  /// означает `false`, а `'true'` явно включает фильтр.
  ///
  /// Пример:
  /// ```dart
  /// params.addIfTrue('overdue', true);   // добавит 'overdue' => 'true'
  /// params.addIfTrue('overdue', false);  // не добавит
  /// params.addIfTrue('overdue', null);   // не добавит
  /// ```
  void addIfTrue(String key, bool? value) {
    if (value == true) {
      this[key] = 'true';
    }
  }
}

/// Расширение для удобного формирования JSON-тела запроса.
///
/// В отличие от query-параметров, тело запроса хранит значения
/// в оригинальных типах (int, String, bool, DateTime), чтобы
/// JSON-сериализация работала корректно.
extension JsonBodyExtension on Map<String, dynamic> {
  /// Добавляет значение в мапу, если оно не null.
  ///
  /// Используется для формирования тела POST/PATCH запросов,
  /// где нужно добавить только переданные пользователем поля.
  ///
  /// Пример:
  /// ```dart
  /// final body = <String, dynamic>{'title': 'Test'};
  /// body.addIfPresent('description', args['description']);
  /// body.addIfPresent('projectId', args['project_id']);
  /// ```
  void addIfPresent(String key, Object? value) {
    if (value != null) {
      this[key] = value;
    }
  }

  /// Копирует значение из одной мапы в другую с возможным переименованием ключа.
  ///
  /// Полезно, когда MCP tool принимает параметры в snake_case (например, `project_id`),
  /// а бэкенд ожидает camelCase (`projectId`).
  ///
  /// Пример:
  /// ```dart
  /// body.copyFrom(args, 'project_id', 'projectId');
  /// // Если args['project_id'] != null, то body['projectId'] = args['project_id']
  /// ```
  void copyFrom(Map<String, dynamic> source, String sourceKey, String targetKey) {
    final value = source[sourceKey];
    if (value != null) {
      this[targetKey] = value;
    }
  }
}
