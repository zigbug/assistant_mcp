import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import '../api_client.dart';
import '../utils/query_helpers.dart';

/// Регистрирует tools для работы с событиями.
///
/// События — жёсткие блоки времени (встречи, созвоны, рабочие блоки, дни
/// рождения). В отличие от задач их нельзя «выполнить», они просто занимают
/// время в плане дня.
///
/// Tools:
/// - `list_events` — список событий с фильтрами
/// - `create_event` — создание события
/// - `update_event` — обновление события
/// - `delete_event` — удаление события
void registerEventsTools(McpServer server, ApiClient api) {
  final logger = Logger('EventsTools');

  // === list_events ===
  server.registerTool(
    'list_events',
    description: 'Получить список событий (встречи, созвоны, рабочие блоки, '
        'дни рождения). По умолчанию — ближайшие 7 дней. Повторяющиеся '
        'события возвращаются в виде шаблона: смотри поля recurrence '
        '(повтор) и by_weekdays (в какие дни повторяется).',
    inputSchema: JsonSchema.object(
      properties: {
        'filter': JsonSchema.string(
          description: 'Что показать: today (только сегодня), '
              'upcoming (будущие, ближайшие days дней) или all (все). '
              'По умолчанию upcoming.',
          enumValues: ['today', 'upcoming', 'all'],
        ),
        'days': JsonSchema.number(
          description: 'Сколько дней вперёд смотреть для filter=upcoming. '
              'По умолчанию 7, максимум 365.',
        ),
      },
    ),
    callback: (args, extra) async {
      try {
        logger.info('list_events called with args: $args');

        final queryParams = <String, String>{};
        queryParams.addIfPresent('filter', args['filter']);
        queryParams.addIfPresent('days', args['days']);

        final result = await api.get('/events', queryParams);
        final events = result as List;

        if (events.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'Событий не найдено.')],
          );
        }

        final buffer = StringBuffer('Найдено событий: ${events.length}\n\n');
        for (final event in events) {
          buffer.writeln('• ID: ${event['id']}');
          buffer.writeln('  Название: ${event['title']}');
          buffer.writeln('  Время: ${_formatRange(event)}');
          if (event['isAllDay'] == true) {
            buffer.writeln('  Весь день');
          }
          if (event['location'] != null) {
            buffer.writeln('  Место: ${event['location']}');
          }
          buffer.writeln('  ${_describeRecurrence(event)}');
          buffer.writeln('  ${_describeOverlap(event)}');
          buffer.writeln();
        }

        return CallToolResult(
          content: [TextContent(text: buffer.toString())],
        );
      } catch (e) {
        logger.severe('Error in list_events: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при получении событий: $e')],
        );
      }
    },
  );

  // === create_event ===
  server.registerTool(
    'create_event',
    description: 'Создать событие — жёсткий блок времени. Обязательные поля: '
        'title и starts_at. Для событий с временем также укажи ends_at '
        '(окончание), иначе бэкенд вернёт ошибку. Для повторения по будням '
        'задайте recurrence="daily" вместе с by_weekdays=["mon","tue","wed",'
        '"thu","fri"]. Короткие события внутри другого блока (звонок, запись '
        'к врачу) помечай can_overlap=true, чтобы они не считались '
        'конфликтом с этим блоком.',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(
          description: 'Название события (обязательное поле, до 200 символов).',
        ),
        'starts_at': JsonSchema.string(
          description: 'Начало в формате ISO 8601 (например '
              '"2026-10-05T10:00:00Z"). Обязательное поле.',
        ),
        'ends_at': JsonSchema.string(
          description: 'Окончание в формате ISO 8601. Обязательно, если '
              'is_all_day не задано. Например "2026-10-05T12:00:00Z".',
        ),
        'is_all_day': JsonSchema.boolean(
          description: 'Событие длится целый день (день рождения, выходной). '
              'Тогда ends_at указывать не нужно. По умолчанию false.',
        ),
        'recurrence': JsonSchema.string(
          description: 'Повторяемость: none, daily, weekly, monthly, yearly. '
              'По умолчанию none. Комбинируй с by_weekdays, чтобы ограничить '
              'серию будними днями.',
          enumValues: ['none', 'daily', 'weekly', 'monthly', 'yearly'],
        ),
        'by_weekdays': JsonSchema.array(
          description: 'В какие дни недели повторяется событие. Например '
              '["mon","tue","wed","thu","fri"] — только будни. Работает '
              'вместе с recurrence.',
          items: JsonSchema.string(
            enumValues: [
              'mon',
              'tue',
              'wed',
              'thu',
              'fri',
              'sat',
              'sun',
            ],
          ),
        ),
        'can_overlap': JsonSchema.boolean(
          description: 'Мягкое событие: может пересекаться с другими и само '
              'не считается конфликтом. Ставь true для коротких дел внутри '
              'другого блока (звонок, запись к врачу, заказ на маркетплейсе). '
              'По умолчанию false — жёсткий блок.',
        ),
        'remind_minutes_before': JsonSchema.number(
          description: 'Напомнить за сколько минут до начала. По умолчанию 30.',
        ),
        'location': JsonSchema.string(
          description: 'Место проведения (адрес, ссылка на звонок и т.п.).',
        ),
      },
      required: ['title', 'starts_at'],
    ),
    callback: (args, extra) async {
      try {
        logger.info('create_event called with args: $args');

        final title = args['title'] as String;
        final startsAt = args['starts_at'] as String;
        final endsAt = args['ends_at'] as String?;
        final isAllDay = args['is_all_day'] as bool? ?? false;

        // ends_at обязателен для событий с временем. Подсказываем это
        // заранее, вместо того чтобы отдавать пользователю сырой HTTP 400.
        if (endsAt == null && !isAllDay) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'Не указан ends_at. Для события с временем нужно указать '
                    'окончание (например "2026-10-05T12:00:00Z"), иначе '
                    'длительность неизвестна. Если это событие на целый день — '
                    'укажи is_all_day=true.',
              ),
            ],
          );
        }

        final body = <String, dynamic>{};
        body['title'] = title;
        body['startsAt'] = startsAt;
        body.addIfPresent('endsAt', endsAt);
        if (isAllDay) {
          body['isAllDay'] = true;
        }
        body.addIfPresent('recurrence', args['recurrence']);
        body.addIfPresent('byWeekdays', args['by_weekdays']);
        body.addIfPresent('canOverlap', args['can_overlap']);
        body.copyFrom(args, 'remind_minutes_before', 'remindMinutesBefore');
        body.addIfPresent('location', args['location']);

        final result = await api.post('/events', body);
        final eventId = result['id'];

        final summary = StringBuffer('✓ Событие успешно создано!\n');
        summary.writeln('ID: $eventId');
        summary.writeln('Название: $title');
        summary.writeln('Время: ${_formatIsoRange(startsAt, endsAt)}');
        final recurrence = args['recurrence'];
        if (recurrence != null && recurrence != 'none') {
          final days = args['by_weekdays'];
          summary.writeln('Повтор: $recurrence'
              '${days is List && days.isNotEmpty ? ' (${days.join(', ')})' : ''}');
        }
        if (args['can_overlap'] == true) {
          summary.writeln('Мягкое: не вытесняет другие блоки из плана');
        }

        return CallToolResult(
          content: [TextContent(text: summary.toString())],
        );
      } catch (e) {
        logger.severe('Error in create_event: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при создании события: $e')],
        );
      }
    },
  );

  // === update_event ===
  server.registerTool(
    'update_event',
    description: 'Обновить существующее событие: время, название, повторение, '
        'признак мягкого события и прочее. Передай пустую строку в ends_at, '
        'чтобы убрать окончание.',
    inputSchema: JsonSchema.object(
      properties: {
        'event_id': JsonSchema.number(
          description: 'ID события для обновления (обязательное поле).',
        ),
        'title': JsonSchema.string(
          description: 'Новое название события.',
        ),
        'starts_at': JsonSchema.string(
          description: 'Новое начало в формате ISO 8601.',
        ),
        'ends_at': JsonSchema.string(
          description: 'Новое окончание в формате ISO 8601. '
              'Передайте пустую строку "", чтобы убрать окончание.',
        ),
        'is_all_day': JsonSchema.boolean(
          description: 'Событие длится целый день.',
        ),
        'recurrence': JsonSchema.string(
          description: 'Новая повторяемость: none, daily, weekly, monthly, '
              'yearly.',
          enumValues: ['none', 'daily', 'weekly', 'monthly', 'yearly'],
        ),
        'by_weekdays': JsonSchema.array(
          description: 'Новый набор дней недели для повторения.',
          items: JsonSchema.string(
            enumValues: [
              'mon',
              'tue',
              'wed',
              'thu',
              'fri',
              'sat',
              'sun',
            ],
          ),
        ),
        'can_overlap': JsonSchema.boolean(
          description: 'Новый признак мягкого события.',
        ),
        'remind_minutes_before': JsonSchema.number(
          description: 'Напомнить за сколько минут до начала.',
        ),
        'location': JsonSchema.string(
          description: 'Новое место проведения.',
        ),
      },
      required: ['event_id'],
    ),
    callback: (args, extra) async {
      try {
        logger.info('update_event called with args: $args');

        final eventId = args['event_id'] as int;

        final body = <String, dynamic>{};
        body.addIfPresent('title', args['title']);
        body.copyFrom(args, 'starts_at', 'startsAt');
        body.addIfPresent('isAllDay', args['is_all_day']);
        body.addIfPresent('recurrence', args['recurrence']);
        body.addIfPresent('byWeekdays', args['by_weekdays']);
        body.addIfPresent('canOverlap', args['can_overlap']);
        body.copyFrom(args, 'remind_minutes_before', 'remindMinutesBefore');
        body.addIfPresent('location', args['location']);

        // ends_at: пустая строка — явное обнуление окончания
        if (args['ends_at'] != null) {
          body['endsAt'] = args['ends_at'] == '' ? null : args['ends_at'];
        }

        if (body.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Не указаны поля для обновления.')],
          );
        }

        await api.patch('/events/$eventId', body);

        return CallToolResult(
          content: [
            TextContent(text: '✓ Событие #$eventId успешно обновлено!'),
          ],
        );
      } catch (e) {
        logger.severe('Error in update_event: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при обновлении события: $e')],
        );
      }
    },
  );

  // === delete_event ===
  server.registerTool(
    'delete_event',
    description: 'Удалить событие. Это необратимая операция — используйте '
        'осторожно.',
    inputSchema: JsonSchema.object(
      properties: {
        'event_id': JsonSchema.number(
          description: 'ID события для удаления (обязательное поле).',
        ),
      },
      required: ['event_id'],
    ),
    annotations: const ToolAnnotations(
      destructiveHint: true,
      title: 'Удалить событие',
    ),
    callback: (args, extra) async {
      try {
        logger.info('delete_event called with args: $args');

        final eventId = args['event_id'] as int;

        await api.delete('/events/$eventId');

        return CallToolResult(
          content: [
            TextContent(text: '✓ Событие #$eventId успешно удалено.'),
          ],
        );
      } catch (e) {
        logger.severe('Error in delete_event: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при удалении события: $e')],
        );
      }
    },
  );
}

/// Форматирует интервал события из ответа бэкенда.
///
/// Бэкенд отдаёт даты как epoch-миллисекунды, поэтому приводим их к
/// читаемому ISO-строке UTC — иначе AI увидит «1791194400000».
String _formatRange(Map<dynamic, dynamic> event) {
  return _formatIsoRange(_isoOf(event['startsAt']), _isoOf(event['endsAt']));
}

/// Приводит значение даты к ISO-строке UTC: принимает epoch-миллисекунды
/// (как отдаёт бэкенд) и уже готовые ISO-строки.
String? _isoOf(Object? raw) {
  if (raw == null) return null;
  if (raw is String) return raw;
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true)
        .toIso8601String();
  }
  return raw.toString();
}

/// Читаемый интервал `начало — окончание` в UTC.
String _formatIsoRange(String? start, String? end) {
  if (start == null) return '?';
  if (end == null) return start;
  return '$start — $end';
}

/// Человекочитаемое описание повторения события.
String _describeRecurrence(Map<dynamic, dynamic> event) {
  final recurrence = event['recurrence'];
  if (recurrence == null || recurrence == 'none') {
    return 'Без повторения';
  }

  final buffer = StringBuffer('Повтор: $recurrence');
  final mask = event['byWeekdays'];
  if (mask is int && mask != 0) {
    buffer.write(' (${_weekdayNames(mask)})');
  }
  return buffer.toString();
}

/// Человекочитаемое описание мягкости события.
String _describeOverlap(Map<dynamic, dynamic> event) {
  return event['canOverlap'] == true
      ? 'Мягкое: не конфликтует с другими событиями'
      : 'Жёсткий блок: конфликтует с другими событиями';
}

/// Раскрывает битовую маску дней недели в список: пн, ср, пт.
String _weekdayNames(int mask) {
  const names = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
  final selected = [
    for (var i = 0; i < names.length; i++)
      if (mask & (1 << i) != 0) names[i],
  ];
  return selected.isEmpty ? '—' : selected.join(', ');
}
