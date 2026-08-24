import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import '../api_client.dart';
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
    description: 'Получить список задач. Можно фильтровать по статусу, проекту, '
        'просроченным задачам или задачам на конкретную дату.',
    inputSchema: JsonSchema.object(
      properties: {
        'status': JsonSchema.string(
          description: 'Статус задач: todo, in_progress, done, backlog. '
              'Если не указан — возвращаются активные задачи.',
          enumValues: ['todo', 'in_progress', 'done', 'backlog'],
        ),
        'project_id': JsonSchema.number(
          description: 'ID проекта для фильтрации задач.',
        ),
        'overdue': JsonSchema.boolean(
          description: 'Если true — вернуть только просроченные задачи.',
        ),
        'scheduled_date': JsonSchema.string(
          description: 'Дата в формате YYYY-MM-DD. Вернуть задачи, '
              'запланированные на эту дату.',
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

        final tasks = await api.get('/tasks', queryParams);

        final tasksList = tasks as List;
        if (tasksList.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'Задач не найдено.')],
          );
        }

        // Форматируем ответ для AI
        final buffer = StringBuffer('Найдено задач: ${tasksList.length}\n\n');
        for (final task in tasksList) {
          buffer.writeln('• ID: ${task['id']}');
          buffer.writeln('  Название: ${task['title']}');
          if (task['description'] != null &&
              task['description'].toString().isNotEmpty) {
            buffer.writeln('  Описание: ${task['description']}');
          }
          buffer.writeln('  Статус: ${task['status']}');
          buffer.writeln(
              '  Важность: ${task['importance']}/5, Срочность: ${task['urgency']}/5');
          if (task['deadline'] != null) {
            buffer.writeln('  Дедлайн: ${task['deadline']}');
          }
          if (task['estimatedMinutes'] != null) {
            buffer.writeln('  Оценка времени: ${task['estimatedMinutes']} мин');
          }
          buffer.writeln();
        }

        return CallToolResult(
          content: [TextContent(text: buffer.toString())],
        );
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
    description: 'Создать новую задачу. Обязательное поле — title. '
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
          description: 'Срочность от 1 (низкая) до 5 (высокая). По умолчанию 2.',
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

        final result = await api.post('/tasks', body);
        final taskId = result['id'];

        return CallToolResult(
          content: [
            TextContent(
              text: '✓ Задача успешно создана!\n'
                  'ID: $taskId\n'
                  'Название: $title',
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
    description: 'Обновить существующую задачу. Можно изменить статус, '
        'название, описание, приоритеты, дедлайн и другие поля.',
    inputSchema: JsonSchema.object(
      properties: {
        'task_id': JsonSchema.number(
          description: 'ID задачи для обновления (обязательное поле).',
        ),
        'title': JsonSchema.string(
          description: 'Новое название задачи.',
        ),
        'description': JsonSchema.string(
          description: 'Новое описание задачи.',
        ),
        'status': JsonSchema.string(
          description: 'Новый статус задачи.',
          enumValues: ['todo', 'in_progress', 'done', 'backlog'],
        ),
        'importance': JsonSchema.number(
          description: 'Новая важность от 1 до 5.',
        ),
        'urgency': JsonSchema.number(
          description: 'Новая срочность от 1 до 5.',
        ),
        'deadline': JsonSchema.string(
          description: 'Новый дедлайн в формате ISO 8601.',
        ),
        'project_id': JsonSchema.number(
          description: 'Новый ID проекта.',
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
        body.addIfPresent('deadline', args['deadline']);
        body.copyFrom(args, 'project_id', 'projectId');

        if (body.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Не указаны поля для обновления.')],
          );
        }

        await api.patch('/tasks/$taskId', body);

        return CallToolResult(
          content: [
            TextContent(text: '✓ Задача #$taskId успешно обновлена!'),
          ],
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
    description: 'Удалить задачу. Это необратимая операция — используйте осторожно.',
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
