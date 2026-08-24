import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import '../api_client.dart';
import '../utils/query_helpers.dart';

/// Регистрирует tools для работы с планами на день.
///
/// Tools:
/// - `get_today_plan` — получить план на сегодня
/// - `generate_plan` — сгенерировать план на указанную дату
/// - `get_plan_stats` — получить статистику по плану
/// - `update_plan_item` — обновить элемент плана (статус, reschedule)
void registerPlansTools(McpServer server, ApiClient api) {
  final logger = Logger('PlansTools');

  // === get_today_plan ===
  server.registerTool(
    'get_today_plan',
    description: 'Получить план на сегодняшний день. Возвращает все элементы '
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
                text: 'План на сегодня ещё не создан. '
                    'Используйте generate_plan для создания плана.',
              ),
            ],
          );
        }

        final buffer = StringBuffer('📅 План на сегодня:\n\n');
        buffer.writeln('Дата: ${plan['date']}');
        buffer.writeln('Статус: ${plan['status']}\n');

        final items = plan['items'] as List? ?? [];
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
                '$statusEmoji $typeEmoji ${item['note'] ?? 'Без названия'}');
            buffer.writeln(
                '   Время: ${item['startTime'] ?? '?'} - ${item['endTime'] ?? '?'}');
            buffer.writeln('   Статус: $status');
            if (item['id'] != null) {
              buffer.writeln('   ID элемента: ${item['id']}');
            }
            buffer.writeln();
          }
        }

        return CallToolResult(
          content: [TextContent(text: buffer.toString())],
        );
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
    description: 'Сгенерировать план на указанную дату. '
        'Собирает задачи, события и просроченные задачи в единый план. '
        'Если план уже существует, он будет пересоздан (идемпотентная операция).',
    inputSchema: JsonSchema.object(
      properties: {
        'date': JsonSchema.string(
          description: 'Дата в формате YYYY-MM-DD. '
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

        final plan = await api.post('/daily-plans/generate', queryParams);

        final buffer = StringBuffer('✓ План успешно сгенерирован!\n\n');
        buffer.writeln('ID плана: ${plan['id']}');
        buffer.writeln('Дата: ${plan['date']}');
        buffer.writeln('Статус: ${plan['status']}\n');

        final items = plan['items'] as List? ?? [];
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
            buffer.writeln('  • $type: $count');
          });
        }

        return CallToolResult(
          content: [TextContent(text: buffer.toString())],
        );
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
    description: 'Получить статистику по плану на день: процент выполнения, '
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

        // Для today нужно сначала получить ID плана
        dynamic stats;
        if (planId == null) {
          final plan = await api.get('/daily-plans/today');
          if (plan == null || plan['id'] == null) {
            return CallToolResult(
              content: [
                TextContent(
                  text: 'План на сегодня не найден. '
                      'Сначала сгенерируйте план через generate_plan.',
                ),
              ],
            );
          }
          stats = await api.get('/daily-plans/${plan['id']}/stats');
        } else {
          stats = await api.get('/daily-plans/$planId/stats');
        }

        final buffer = StringBuffer('📊 Статистика плана:\n\n');
        buffer.writeln('Дата: ${stats['date']}');
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
            '  • Запланировано: ${stats['timeEstimatedMinutes'] ?? 0} мин');
        buffer.writeln('  • Затрачено: ${stats['timeSpentMinutes'] ?? 0} мин');

        return CallToolResult(
          content: [TextContent(text: buffer.toString())],
        );
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
    description: 'Обновить элемент плана: изменить статус, добавить заметку, '
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
