import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import '../api_client.dart';
import '../utils/query_helpers.dart';

/// Регистрирует tools для работы с проектами.
///
/// Бэкенд уже умеет всё это (`GET/POST/PATCH/DELETE /projects`), но до сих пор
/// проект был доступен только как `project_id` в задачах. Из-за этого модель
/// не могла ни создать проект, ни даже посмотреть, какие проекты есть, и
/// отвечала пользователю «инструментов для проектов нет».
///
/// Tools:
/// - `list_projects` — список проектов (активные / все / только архивные)
/// - `create_project` — создать проект
/// - `get_project` — один проект со счётчиком задач
/// - `update_project` — переименовать, перекрасить, архивировать/восстановить
/// - `delete_project` — удалить проект (только если к нему не привязаны задачи)
void registerProjectsTools(McpServer server, ApiClient api) {
  final logger = Logger('ProjectsTools');

  String archiveBadge(Map project) =>
      project['isArchived'] == true ? ' [архив]' : '';

  String projectLine(Map project) =>
      '• ID: ${project['id']}  «${project['name']}»${archiveBadge(project)}'
      '${project['color'] != null ? '  цвет ${project['color']}' : ''}';

  // === list_projects ===
  server.registerTool(
    'list_projects',
    description:
        'Получить список проектов. Вызывай ДО создания нового проекта: если '
        'подходящий уже есть (например, «Починка двигателя»), переиспользуй '
        'его, а не плоди дубли.',
    inputSchema: JsonSchema.object(
      properties: {
        'include_archived': JsonSchema.boolean(
          description:
              'Если true — вернуть и активные, и архивные проекты. '
              'По умолчанию только активные.',
        ),
        'archived_only': JsonSchema.boolean(
          description: 'Если true — вернуть только архивные проекты.',
        ),
      },
    ),
    callback: (args, extra) async {
      try {
        logger.info('list_projects called with args: $args');

        final queryParams = <String, String>{};
        final archivedOnly = args['archived_only'] as bool?;
        queryParams.addIfTrue('archived', archivedOnly);
        if (archivedOnly != true) {
          queryParams.addIfTrue(
            'include_archived',
            args['include_archived'] as bool?,
          );
        }

        final projects = await api.get('/projects', queryParams) as List;

        if (projects.isEmpty) {
          return CallToolResult(
            content: [
              TextContent(
                text: archivedOnly == true
                    ? 'Архивных проектов нет.'
                    : 'Проектов пока нет. Создай первый через create_project.',
              ),
            ],
          );
        }

        final buffer = StringBuffer('Проектов: ${projects.length}\n\n');
        for (final project in projects) {
          buffer.writeln(projectLine(project as Map));
        }
        buffer.write(
          '\nПривязать задачу к проекту: project_id в create_task/update_task. '
          'Задачи проекта: list_tasks с project_id.',
        );

        return CallToolResult(content: [TextContent(text: buffer.toString())]);
      } on ApiException catch (e) {
        logger.severe('ApiException in list_projects: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при получении проектов: $e')],
        );
      } catch (e) {
        logger.severe('Error in list_projects: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при получении проектов: $e')],
        );
      }
    },
  );

  // === create_project ===
  server.registerTool(
    'create_project',
    description:
        'Создать проект. Вызывай, когда пользователь описывает многошаговую '
        'цель: починка, ремонт, переезд, запуск, внедрение. Один проект — одна '
        'большая цель, этапы внутри неё оформляй задачами с этим project_id.',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(
          description:
              'Название проекта, 1–100 символов. Короткое и понятное: '
              '«Починка двигателя», не «Разное» и не «Задача».',
        ),
        'color': JsonSchema.string(
          description: 'Необязательный цвет для UI, hex: #FF5733.',
        ),
      },
      required: ['name'],
    ),
    callback: (args, extra) async {
      try {
        logger.info('create_project called with args: $args');

        final body = <String, dynamic>{'name': args['name']};
        if (args['color'] != null) body['color'] = args['color'];

        final result =
            await api.post('/projects', body) as Map<String, dynamic>;

        final buffer = StringBuffer('✅ Проект создан.\n\n');
        buffer.writeln('ID: ${result['id']}');
        buffer.writeln('Название: ${args['name']}');
        buffer.write(
          '\nДальше: разбей цель на этапы и создай их задачами '
          '(create_task с project_id=${result['id']}), затем собери план '
          'дня через generate_plan.',
        );

        return CallToolResult(content: [TextContent(text: buffer.toString())]);
      } on ApiException catch (e) {
        logger.severe('ApiException in create_project: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при создании проекта: $e')],
        );
      } catch (e) {
        logger.severe('Error in create_project: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при создании проекта: $e')],
        );
      }
    },
  );

  // === get_project ===
  server.registerTool(
    'get_project',
    description:
        'Один проект: название, цвет, статус архива и сколько у него задач '
        '(всего / выполнено / в работе / к выполнению).',
    inputSchema: JsonSchema.object(
      properties: {
        'project_id': JsonSchema.number(description: 'ID проекта.'),
      },
      required: ['project_id'],
    ),
    callback: (args, extra) async {
      try {
        final id = args['project_id'];
        logger.info('get_project called with id: $id');

        final project = await api.get('/projects/$id') as Map<String, dynamic>;
        final stats = (project['taskStats'] as Map?) ?? const {};

        final buffer = StringBuffer('📁 Проект\n\n');
        buffer.writeln('ID: ${project['id']}');
        buffer.writeln('Название: ${project['name']}');
        if (project['color'] != null) buffer.writeln('Цвет: ${project['color']}');
        buffer.writeln('Архив: ${project['isArchived'] == true ? 'да' : 'нет'}');
        buffer.write(
          '\nЗадачи: всего ${project['taskCount'] ?? stats['total'] ?? 0}, '
          'выполнено ${stats['done'] ?? 0}, '
          'в работе ${stats['in_progress'] ?? 0}, '
          'к выполнению ${stats['todo'] ?? 0}.\n',
        );
        buffer.write('Список задач: list_tasks с project_id=$id.');

        return CallToolResult(content: [TextContent(text: buffer.toString())]);
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'Проект с таким id не найден. Посмотри существующие: '
                    'list_projects.',
              ),
            ],
          );
        }
        logger.severe('ApiException in get_project: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при получении проекта: $e')],
        );
      } catch (e) {
        logger.severe('Error in get_project: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при получении проекта: $e')],
        );
      }
    },
  );

  // === update_project ===
  server.registerTool(
    'update_project',
    description:
        'Изменить проект: переименовать, поменять цвет, архивировать или '
        'восстановить. Передай только то, что меняешь.',
    inputSchema: JsonSchema.object(
      properties: {
        'project_id': JsonSchema.number(description: 'ID проекта.'),
        'name': JsonSchema.string(
          description: 'Новое название, 1–100 символов.',
        ),
        'color': JsonSchema.string(
          description: 'Новый цвет, hex: #FF5733.',
        ),
        'archived': JsonSchema.boolean(
          description:
              'true — архивировать (проект уходит из списка активных, задачи '
              'остаются). false — восстановить из архива.',
        ),
      },
      required: ['project_id'],
    ),
    callback: (args, extra) async {
      try {
        final id = args['project_id'];
        logger.info('update_project called with args: $args');

        final archived = args['archived'] as bool?;
        if (archived != null) {
          final action = archived ? 'archive' : 'unarchive';
          final updated =
              await api.patch('/projects/$id/$action', {}) as Map;
          final label = archived ? 'архивирован' : 'восстановлен';
          return CallToolResult(
            content: [
              TextContent(
                text: '✅ Проект «${updated['name']}» $label.',
              ),
            ],
          );
        }

        final body = <String, dynamic>{};
        if (args['name'] != null) body['name'] = args['name'];
        if (args['color'] != null) body['color'] = args['color'];

        if (body.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'Нечего менять: передай name, color или archived.',
              ),
            ],
          );
        }

        final updated =
            await api.patch('/projects/$id', body) as Map<String, dynamic>;

        return CallToolResult(
          content: [
            TextContent(
              text: '✅ Проект обновлён.\n\nID: ${updated['id']}\n'
                  'Название: ${updated['name']}'
                  '${updated['color'] != null ? '\nЦвет: ${updated['color']}' : ''}',
            ),
          ],
        );
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'Проект с таким id не найден. list_projects.'),
            ],
          );
        }
        logger.severe('ApiException in update_project: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при обновлении проекта: $e')],
        );
      } catch (e) {
        logger.severe('Error in update_project: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при обновлении проекта: $e')],
        );
      }
    },
  );

  // === delete_project ===
  server.registerTool(
    'delete_project',
    description:
        'Удалить проект безвозвратно. Бэкенд откажется (409), если к проекту '
        'привязаны задачи: сначала сними привязку или перенеси задачи. '
        'Обычнее архивировать через update_project.',
    inputSchema: JsonSchema.object(
      properties: {
        'project_id': JsonSchema.number(description: 'ID проекта.'),
      },
      required: ['project_id'],
    ),
    callback: (args, extra) async {
      final id = args['project_id'];
      try {
        logger.info('delete_project called with id: $id');

        await api.delete('/projects/$id');

        return CallToolResult(
          content: [TextContent(text: '✅ Проект #$id удалён.')],
        );
      } on ApiException catch (e) {
        if (e.statusCode == 409) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'Удалить нельзя: к проекту привязаны задачи. '
                    'Посмотри их (list_tasks с project_id=$id), сними '
                    'привязку или перенеси — потом удалишь. Если задачи не '
                    'нужны, сначала удали их (delete_task).',
              ),
            ],
          );
        }
        if (e.statusCode == 404) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Проект с таким id не найден.')],
          );
        }
        logger.severe('ApiException in delete_project: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при удалении проекта: $e')],
        );
      } catch (e) {
        logger.severe('Error in delete_project: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при удалении проекта: $e')],
        );
      }
    },
  );
}