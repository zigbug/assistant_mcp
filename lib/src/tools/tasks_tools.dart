import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import '../api_client.dart';
import '../utils/date_format.dart';
import '../utils/query_helpers.dart';

/// Регистрирует tools для работы с задачами.
///
/// Tools:
/// - `list_tasks` — список задач с фильтрами
/// - `create_task` — создание новой задачи
/// - `update_task` — обновление задачи
/// - `delete_task` — удаление задачи
void registerTasksTools(McpServer server, ApiClient api) {
  final logger = Logger('TasksTools');

  // === list_tasks ===
  server.registerTool(
    'list_tasks',
    description:
        'Получить список задач. Можно фильтровать по статусу, проекту, '
        'просроченным задачам, задачам на конкретную дату или шаблонам '
        'повторяющихся задач.',
    inputSchema: JsonSchema.object(
      properties: {
        'status': JsonSchema.string(
          description:
              'Статус задач: todo, in_progress, waiting, done, '
              'cancelled, backlog. Если не указан — возвращаются активные '
              'задачи.',
          enumValues: [
            'todo',
            'in_progress',
            'waiting',
            'done',
            'cancelled',
            'backlog',
          ],
        ),
        'project_id': JsonSchema.number(
          description: 'ID проекта для фильтрации задач.',
        ),
        'overdue': JsonSchema.boolean(
          description: 'Если true — вернуть только просроченные задачи.',
        ),
        'scheduled_date': JsonSchema.string(
          description:
              'Дата в формате YYYY-MM-DD. Вернуть задачи, '
              'запланированные на эту дату.',
        ),
        'include_templates': JsonSchema.boolean(
          description:
              'Если true — включить в выдачу шаблоны повторяющихся '
              'задач (по умолчанию скрыты).',
        ),
      },
    ),
    callback: (args, extra) async {
      try {
        logger.info('list_tasks called with args: $args');

        // Формируем query-параметры с помощью хелперов
        final queryParams = <String, String>{};
        queryParams.addIfPresent('status', args['status']);
        queryParams.addIfPresent('project_id', args['project_id']);
        queryParams.addIfTrue('overdue', args['overdue'] as bool?);
        queryParams.addIfPresent('scheduled', args['scheduled_date']);
        queryParams.addIfTrue(
          'include_templates',
          args['include_templates'] as bool?,
        );

        final tasks = await api.get('/tasks', queryParams);

        final tasksList = tasks as List;
        if (tasksList.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'Задач не найдено.')],
          );
        }

        // Форматируем ответ для AI
        final buffer = StringBuffer('Найдено задач: ${tasksList.length}\n\n');
        if (!queryParams.isNotEmpty) {
          buffer.writeln(
            'ВНИМАНИЕ: запрошены все задачи без фильтров. '
            'Если нужно меньше данных — укажи status, project_id, '
            'scheduled_date или overdue.\n\n',
          );
        }
        for (final task in tasksList) {
          buffer.writeln('• ID: ${task['id']}');
          buffer.writeln('  Название: ${task['title']}');
          if (task['description'] != null &&
              task['description'].toString().isNotEmpty) {
            buffer.writeln('  Описание: ${task['description']}');
          }
          buffer.writeln('  Статус: ${task['status']}');
          buffer.writeln(
            '  Важность: ${task['importance']}/5, Срочность: ${task['urgency']}/5',
          );
          if (task['deadline'] != null) {
            buffer.writeln(
              '  Дедлайн: ${humanDate(task['deadline'])} '
              '(${formatRange(task['deadline'], null)})',
            );
          }
          if (task['estimatedMinutes'] != null) {
            buffer.writeln('  Оценка времени: ${task['estimatedMinutes']} мин');
          }
          if (task['scheduledTime'] != null) {
            final start = task['scheduledTime'] as int;
            final hh = (start ~/ 60).toString().padLeft(2, '0');
            final mm = (start % 60).toString().padLeft(2, '0');
            buffer.writeln('  Время начала: $hh:$mm');
          }
          if (task['scheduledDate'] != null) {
            buffer.writeln(
              '  Запланировано: ${humanLocalDate(task['scheduledDate'])}',
            );
          }
          final recurrence = task['recurrence'];
          if (recurrence != null && recurrence != 'none') {
            buffer.writeln(
              '  Повторение: $recurrence '
              '(каждые ${task['repeatInterval'] ?? 1})',
            );
            if (task['repeatEndDate'] != null) {
              buffer.writeln(
                '  Повтор до: ${humanLocalDate(task['repeatEndDate'])}',
              );
            }
          }
          if (task['parentId'] != null) {
            buffer.writeln('  Экземпляр шаблона #${task['parentId']}');
          }
          buffer.writeln();
        }

        return CallToolResult(content: [TextContent(text: buffer.toString())]);
      } catch (e) {
        logger.severe('Error in list_tasks: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при получении задач: $e')],
        );
      }
    },
  );

  // === create_task ===
  server.registerTool(
    'create_task',
    description:
        'Создать новую задачу. Обязательное поле — title. '
        'Остальные поля опциональны.',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(
          description: 'Название задачи (обязательное поле).',
        ),
        'description': JsonSchema.string(
          description: 'Подробное описание задачи.',
        ),
        'project_id': JsonSchema.number(
          description: 'ID проекта, к которому привязать задачу.',
        ),
        'importance': JsonSchema.number(
          description: 'Важность от 1 (низкая) до 5 (высокая). По умолчанию 2.',
        ),
        'urgency': JsonSchema.number(
          description:
              'Срочность от 1 (низкая) до 5 (высокая). По умолчанию 2.',
        ),
        'deadline': JsonSchema.string(
          description: 'Дедлайн в формате ISO 8601 (YYYY-MM-DDTHH:MM:SSZ).',
        ),
        'scheduled_date': JsonSchema.string(
          description: 'Дата, на которую запланирована задача (YYYY-MM-DD).',
        ),
        'estimated_minutes': JsonSchema.number(
          description: 'Оценка времени выполнения в минутах.',
        ),
        'scheduled_time': JsonSchema.string(
          description:
              'Время начала в течение дня в формате "HH:MM" (например, '
              '"09:30"). Планировщик поставит задачу ровно на этот час. '
              'Требует также estimated_minutes: без длительности слот '
              'неизвестен. Если слот занят — задача останется без времени, '
              'а не переедет на другое.',
        ),
        'recurrence': JsonSchema.string(
          description:
              'Повторяемость задачи (создаёт шаблон повторений): '
              'none, daily, weekly, monthly, yearly. По умолчанию none. '
              'Если задано не none — создаётся шаблон, из которого '
              'материализуются экземпляры на 30 дней вперёд.',
          enumValues: ['none', 'daily', 'weekly', 'monthly', 'yearly'],
        ),
        'repeat_interval': JsonSchema.number(
          description:
              'Интервал повтора: каждые N дней/недель/месяцев/лет. '
              'По умолчанию 1. Должно быть >= 1. Применяется вместе с '
              'recurrence.',
        ),
        'repeat_end_date': JsonSchema.string(
          description:
              'Дата окончания серии повторов в формате ISO 8601. '
              'Опционально. Применяется вместе с recurrence.',
        ),
        'parent_id': JsonSchema.number(
          description:
              'ID шаблона-родителя, если создаётся экземпляр '
              'повторяющейся задачи.',
        ),
      },
      required: ['title'],
    ),
    callback: (args, extra) async {
      try {
        logger.info('create_task called with args: $args');

        final title = args['title'] as String;

        // Формируем тело запроса с помощью хелперов
        final body = <String, dynamic>{'title': title};
        body.addIfPresent('description', args['description']);
        body.copyFrom(args, 'project_id', 'projectId');
        body.addIfPresent('importance', args['importance']);
        body.addIfPresent('urgency', args['urgency']);
        body.addIfPresent('deadline', args['deadline']);
        body.copyFrom(args, 'scheduled_date', 'scheduledDate');
        body.copyFrom(args, 'estimated_minutes', 'estimatedMinutes');
        body.copyFrom(args, 'scheduled_time', 'scheduledTime');
        body.addIfPresent('recurrence', args['recurrence']);
        body.copyFrom(args, 'repeat_interval', 'repeatInterval');
        body.copyFrom(args, 'repeat_end_date', 'repeatEndDate');
        body.copyFrom(args, 'parent_id', 'parentId');

        final result = await api.post('/tasks', body);
        final taskId = result['id'];

        final recurrence = args['recurrence'];
        final isRecurring = recurrence != null && recurrence != 'none';

        return CallToolResult(
          content: [
            TextContent(
              text:
                  '✓ Задача успешно создана!\n'
                  'ID: $taskId\n'
                  'Название: $title\n'
                  '${isRecurring ? 'Повторение: $recurrence (каждые ${args['repeat_interval'] ?? 1})\n' : ''}',
            ),
          ],
        );
      } catch (e) {
        logger.severe('Error in create_task: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при создании задачи: $e')],
        );
      }
    },
  );

  // === update_task ===
  server.registerTool(
    'update_task',
    description:
        'Обновить существующую задачу. Можно изменить статус, '
        'название, описание, приоритеты, дедлайн и другие поля.',
    inputSchema: JsonSchema.object(
      properties: {
        'task_id': JsonSchema.number(
          description: 'ID задачи для обновления (обязательное поле).',
        ),
        'title': JsonSchema.string(description: 'Новое название задачи.'),
        'description': JsonSchema.string(description: 'Новое описание задачи.'),
        'status': JsonSchema.string(
          description: 'Новый статус задачи.',
          enumValues: [
            'todo',
            'in_progress',
            'waiting',
            'done',
            'cancelled',
            'backlog',
          ],
        ),
        'importance': JsonSchema.number(
          description: 'Новая важность от 1 до 5.',
        ),
        'urgency': JsonSchema.number(description: 'Новая срочность от 1 до 5.'),
        'deadline': JsonSchema.string(
          description:
              'Новый дедлайн в формате ISO 8601. '
              'Передайте пустую строку "" чтобы убрать дедлайн.',
        ),
        'project_id': JsonSchema.number(description: 'Новый ID проекта.'),
        'scheduled_date': JsonSchema.string(
          description:
              'Новая дата, на которую запланирована задача '
              '(YYYY-MM-DD).',
        ),
        'estimated_minutes': JsonSchema.number(
          description:
              'Новая оценка времени выполнения в минутах. '
              'Именно она превращает задачу из «на весь день» в блок '
              'в расписании.',
        ),
        'scheduled_time': JsonSchema.string(
          description:
              'Новое время начала в течение дня, "HH:MM". Передайте пустую '
              'строку "" чтобы убрать фиксированное время и вернуть '
              'задачу в автоматическую раскладку.',
        ),
        'recurrence': JsonSchema.string(
          description:
              'Повторяемость задачи: none, daily, weekly, monthly, '
              'yearly. Установите "none", чтобы остановить серию повторов.',
          enumValues: ['none', 'daily', 'weekly', 'monthly', 'yearly'],
        ),
        'repeat_interval': JsonSchema.number(
          description:
              'Интервал повтора: каждые N дней/недель/месяцев/лет. '
              'Должно быть >= 1.',
        ),
        'repeat_end_date': JsonSchema.string(
          description:
              'Дата окончания серии повторов в формате ISO 8601. '
              'Передайте пустую строку "" чтобы убрать ограничение.',
        ),
      },
      required: ['task_id'],
    ),
    callback: (args, extra) async {
      try {
        logger.info('update_task called with args: $args');

        final taskId = args['task_id'] as int;

        final body = <String, dynamic>{};
        body.addIfPresent('title', args['title']);
        body.addIfPresent('description', args['description']);
        body.addIfPresent('status', args['status']);
        body.addIfPresent('importance', args['importance']);
        body.addIfPresent('urgency', args['urgency']);
        body.copyFrom(args, 'project_id', 'projectId');
        body.addIfPresent('recurrence', args['recurrence']);
        body.copyFrom(args, 'repeat_interval', 'repeatInterval');

        // Дедлайн и repeat_end_date: поддерживаем явное обнуление пустой строкой
        if (args['deadline'] != null) {
          body['deadline'] = args['deadline'] == '' ? null : args['deadline'];
        }
        if (args['repeat_end_date'] != null) {
          body['repeatEndDate'] = args['repeat_end_date'] == ''
              ? null
              : args['repeat_end_date'];
        }
        if (args['scheduled_date'] != null) {
          body['scheduledDate'] = args['scheduled_date'];
        }
        body.copyFrom(args, 'estimated_minutes', 'estimatedMinutes');
        // Пустая строка сбрасывает фиксированное время начала.
        if (args['scheduled_time'] != null) {
          body['scheduledTime'] = args['scheduled_time'] == ''
              ? null
              : args['scheduled_time'];
        }

        if (body.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Не указаны поля для обновления.')],
          );
        }

        await api.patch('/tasks/$taskId', body);

        return CallToolResult(
          content: [TextContent(text: '✓ Задача #$taskId успешно обновлена!')],
        );
      } catch (e) {
        logger.severe('Error in update_task: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при обновлении задачи: $e')],
        );
      }
    },
  );

  // === delete_task ===
  server.registerTool(
    'delete_task',
    description:
        'Удалить задачу. Это необратимая операция — используйте осторожно.',
    inputSchema: JsonSchema.object(
      properties: {
        'task_id': JsonSchema.number(
          description: 'ID задачи для удаления (обязательное поле).',
        ),
      },
      required: ['task_id'],
    ),
    annotations: const ToolAnnotations(
      destructiveHint: true,
      title: 'Удалить задачу',
    ),
    callback: (args, extra) async {
      try {
        logger.info('delete_task called with args: $args');

        final taskId = args['task_id'] as int;

        await api.delete('/tasks/$taskId');

        return CallToolResult(
          content: [TextContent(text: '✓ Задача #$taskId успешно удалена.')],
        );
      } catch (e) {
        logger.severe('Error in delete_task: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при удалении задачи: $e')],
        );
      }
    },
  );
}
