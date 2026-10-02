import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import '../api_client.dart';
import '../utils/date_format.dart';
import '../utils/query_helpers.dart';

/// Регистрирует tools для работы с планами на день.
///
/// Tools:
/// - `get_today_plan` — получить план на сегодня
/// - `generate_plan` — сгенерировать план на указанную дату
/// - `get_plan_stats` — получить статистику по плану
/// - `update_plan_item` — обновить элемент плана (статус, reschedule)
/// - `delete_plan` — удалить план дня вместе со всеми элементами
void registerPlansTools(McpServer server, ApiClient api) {
  final logger = Logger('PlansTools');

  // === get_today_plan ===
  server.registerTool(
    'get_today_plan',
    description:
        'Получить план на сегодняшний день. Возвращает все элементы '
        '(задачи, события, перерывы) с их статусами и временными слотами.',
    inputSchema: JsonSchema.object(),
    callback: (args, extra) async {
      try {
        logger.info('get_today_plan called');

        final plan = await api.get('/daily-plans/today');

        if (plan == null || (plan is Map && plan.isEmpty)) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'План на сегодня ещё не создан. '
                    'Используйте generate_plan для создания плана.',
              ),
            ],
          );
        }

        // Бэкенд отдаёт `{plan: {...}, items: [...]}`: метаданные плана лежат
        // во вложенном объекте, а список элементов — на верхнем уровне.
        final meta = _planMeta(plan);
        final items = plan['items'] as List? ?? [];

        final buffer = StringBuffer('📅 План на сегодня:\n\n');
        buffer.writeln('Дата: ${localDateOnly(meta['date'])}');
        buffer.writeln('Статус: ${meta['status']}\n');

        if (items.isEmpty) {
          buffer.writeln('Элементов в плане нет.');
        } else {
          buffer.writeln('Элементы (${items.length}):\n');
          for (final item in items) {
            final status = item['status'] ?? 'planned';
            final statusEmoji = _statusEmoji(status);
            final type = item['itemType'] ?? 'unknown';
            final typeEmoji = _typeEmoji(type);

            buffer.writeln(
              '$statusEmoji $typeEmoji ${item['note'] ?? 'Без названия'}',
            );
            buffer.writeln('   Время: ${_itemRange(item)}');
            buffer.writeln('   Статус: $status');
            if (item['id'] != null) {
              buffer.writeln('   ID элемента: ${item['id']}');
            }
            buffer.writeln();
          }
        }

        return CallToolResult(content: [TextContent(text: buffer.toString())]);
      } catch (e) {
        logger.severe('Error in get_today_plan: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при получении плана: $e')],
        );
      }
    },
  );

  // === generate_plan ===
  server.registerTool(
    'generate_plan',
    description:
        'Сгенерировать план на указанную дату. '
        'Собирает задачи, события и просроченные задачи в единый план. '
        'Если план уже существует, он будет пересоздан (идемпотентная операция).',
    inputSchema: JsonSchema.object(
      properties: {
        'date': JsonSchema.string(
          description:
              'Дата в формате YYYY-MM-DD. '
              'Если не указана — используется сегодняшняя дата.',
        ),
      },
    ),
    callback: (args, extra) async {
      try {
        logger.info('generate_plan called with args: $args');

        // Формируем query-параметры
        final queryParams = <String, String>{};
        queryParams.addIfPresent('date', args['date']);

        // Дата уходит в query: бэкенд читает `date` из request.url.queryParameters,
        // поэтому в теле её быть не должно.
        final result = await api.post(
          '/daily-plans/generate',
          const {},
          queryParams: queryParams.isEmpty ? null : queryParams,
        );

        // Ответ: `{plan: {...}, items: [...], stats: {...}}`.
        final meta = _planMeta(result);
        final items = result['items'] as List? ?? [];

        final buffer = StringBuffer('✓ План успешно сгенерирован!\n\n');
        buffer.writeln('ID плана: ${meta['id']}');
        buffer.writeln('Дата: ${localDateOnly(meta['date'])}');
        buffer.writeln('Статус: ${meta['status']}\n');

        buffer.writeln('Элементов в плане: ${items.length}');

        // Краткая статистика
        final stats = <String, int>{};
        for (final item in items) {
          final type = item['itemType'] ?? 'unknown';
          stats[type] = (stats[type] ?? 0) + 1;
        }
        if (stats.isNotEmpty) {
          buffer.writeln('\nСостав:');
          stats.forEach((type, count) {
            buffer.writeln('  • ${_typeEmoji(type)} $type: $count');
          });
        }

        if (items.isNotEmpty) {
          buffer.writeln('\nЭлементы:');
          for (final item in items) {
            final status = item['status'] ?? 'planned';
            final note = item['note'] ?? 'Без названия';
            buffer.writeln(
              '  ${_statusEmoji(status)} ${_typeEmoji(item['itemType'] ?? '')} $note',
            );
            buffer.writeln('     ${_itemRange(item)}');
          }
        }

        buffer.writeln(
          '\nВнимание: генерация плана пересоздаёт его с нуля — прежние '
          'отметки о выполнении и заметки будут потеряны.',
        );

        return CallToolResult(content: [TextContent(text: buffer.toString())]);
      } catch (e) {
        logger.severe('Error in generate_plan: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при генерации плана: $e')],
        );
      }
    },
  );

  // === get_plan_stats ===
  server.registerTool(
    'get_plan_stats',
    description:
        'Получить статистику по плану на день: процент выполнения, '
        'разбивку по статусам, затраченное и запланированное время.',
    inputSchema: JsonSchema.object(
      properties: {
        'plan_id': JsonSchema.number(
          description: 'ID плана. Если не указан — берётся план на сегодня.',
        ),
      },
    ),
    callback: (args, extra) async {
      try {
        logger.info('get_plan_stats called with args: $args');

        final planId = args['plan_id'];

        // Для today нужно сначала получить ID плана.
        dynamic stats;
        if (planId == null) {
          final response = await api.get('/daily-plans/today');
          // Метаданные плана — во вложенном объекте `plan`.
          final meta = _planMeta(response);
          if (meta['id'] == null) {
            return CallToolResult(
              content: [
                TextContent(
                  text:
                      'План на сегодня не найден. '
                      'Сначала сгенерируйте план через generate_plan.',
                ),
              ],
            );
          }
          stats = await api.get('/daily-plans/${meta['id']}/stats');
        } else {
          stats = await api.get('/daily-plans/$planId/stats');
        }

        final buffer = StringBuffer('📊 Статистика плана:\n\n');
        buffer.writeln('Дата: ${localDateOnly(stats['date'])}');
        buffer.writeln('Общий статус: ${stats['status']}\n');

        buffer.writeln('Всего элементов: ${stats['totalItems']}');
        buffer.writeln('Выполнено: ${stats['completedPercent']}%\n');

        buffer.writeln('Разбивка по статусам:');
        final byStatus = stats['byStatus'] as Map? ?? {};
        byStatus.forEach((status, count) {
          if (count > 0) {
            buffer.writeln('  • $status: $count');
          }
        });

        buffer.writeln('\nВремя:');
        buffer.writeln(
          '  • Запланировано: ${stats['timeEstimatedMinutes'] ?? 0} мин',
        );
        buffer.writeln('  • Затрачено: ${stats['timeSpentMinutes'] ?? 0} мин');

        return CallToolResult(content: [TextContent(text: buffer.toString())]);
      } catch (e) {
        logger.severe('Error in get_plan_stats: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при получении статистики: $e')],
        );
      }
    },
  );

  // === update_plan_item ===
  server.registerTool(
    'update_plan_item',
    description:
        'Обновить элемент плана: изменить статус, добавить заметку, '
        'перенести на другое время.',
    inputSchema: JsonSchema.object(
      properties: {
        'item_id': JsonSchema.number(
          description: 'ID элемента плана (обязательное поле).',
        ),
        'status': JsonSchema.string(
          description: 'Новый статус элемента.',
          enumValues: [
            'planned',
            'inProgress',
            'done',
            'skipped',
            'moved',
            'cancelled',
          ],
        ),
        'note': JsonSchema.string(
          description: 'Заметка к элементу (например, причина пропуска).',
        ),
        'start_time': JsonSchema.string(
          description: 'Новое время начала в формате ISO 8601.',
        ),
        'end_time': JsonSchema.string(
          description: 'Новое время окончания в формате ISO 8601.',
        ),
      },
      required: ['item_id'],
    ),
    callback: (args, extra) async {
      try {
        logger.info('update_plan_item called with args: $args');

        final itemId = args['item_id'] as int;

        final body = <String, dynamic>{};
        body.addIfPresent('status', args['status']);
        body.addIfPresent('note', args['note']);
        body.copyFrom(args, 'start_time', 'startTime');
        body.copyFrom(args, 'end_time', 'endTime');

        if (body.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Не указаны поля для обновления.')],
          );
        }

        await api.patch('/daily-plans/items/$itemId', body);

        return CallToolResult(
          content: [
            TextContent(text: '✓ Элемент плана #$itemId успешно обновлён!'),
          ],
        );
      } catch (e) {
        logger.severe('Error in update_plan_item: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при обновлении элемента: $e')],
        );
      }
    },
  );

  // === delete_plan ===
  server.registerTool(
    'delete_plan',
    description:
        'Удалить план дня вместе со всеми его элементами. '
        'Это необратимая операция: отметки о выполнении и заметки будут потеряны. '
        'Используй, чтобы убрать ошибочно созданный план или сбросить день перед '
        'новой генерацией.',
    inputSchema: JsonSchema.object(
      properties: {
        'plan_id': JsonSchema.number(
          description: 'ID плана (обязательное поле).',
        ),
      },
      required: ['plan_id'],
    ),
    callback: (args, extra) async {
      try {
        logger.info('delete_plan called with args: $args');

        final planId = args['plan_id'] as int;

        await api.delete('/daily-plans/$planId');

        return CallToolResult(
          content: [
            TextContent(text: '🗑️ План #$planId удалён вместе с элементами.'),
          ],
        );
      } catch (e) {
        logger.severe('Error in delete_plan: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при удалении плана: $e')],
        );
      }
    },
  );
}

/// Достаёт метаданные плана из ответа бэкенда.
///
/// Эндпоинты планов отдают `{plan: {...}, items: [...], stats: {...}}` —
/// дата, статус и id лежат во вложенном объекте `plan`, а список элементов
/// на верхнем уровне. Если сервер когда-нибудь начнёт отдавать метаданные
/// плоско, функция вернёт сам ответ.
Map<String, dynamic> _planMeta(Object? response) {
  if (response is! Map) return const {};
  final source = response['plan'] is Map ? response['plan'] as Map : response;
  return source.map((key, value) => MapEntry(key.toString(), value));
}

/// Время элемента плана в читаемом виде.
///
/// Задача без `estimatedMinutes` кладётся в план на полночь своей даты и не
/// имеет длительности. Печатать для неё «2026-10-01T21:00:00.000Z» — вводить
/// в заблуждение: это не момент времени, а маркер дня. Поэтому для таких
/// задач честно сообщаем, что конкретное время не назначено.
String _itemRange(Map<dynamic, dynamic> item) {
  final isTask = (item['itemType'] ?? '') == 'task';
  if (isTask && item['endTime'] == null) {
    return 'время не назначено (задача на весь день)';
  }
  return formatRange(item['startTime'], item['endTime']);
}

/// Возвращает эмодзи для статуса элемента плана.
String _statusEmoji(String status) {
  return switch (status) {
    'planned' => '📋',
    'inProgress' => '▶️',
    'done' => '✅',
    'skipped' => '⏭️',
    'moved' => '📅',
    'cancelled' => '❌',
    _ => '❓',
  };
}

/// Возвращает эмодзи для типа элемента плана.
String _typeEmoji(String type) {
  return switch (type) {
    'task' => '📝',
    'event' => '📆',
    'break' => '☕',
    _ => '📌',
  };
}
