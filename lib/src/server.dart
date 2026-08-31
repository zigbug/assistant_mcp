import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import 'api_client.dart';
import 'config.dart';
import 'tools/plans_tools.dart';
import 'tools/tasks_tools.dart';
import 'tools/time_tools.dart';

/// Создаёт и настраивает MCP-сервер.
///
/// Регистрирует все tools, resources и prompts.
/// Сервер использует stdio транспорт для локального взаимодействия
/// с MCP-клиентами (Qwen Desktop, Claude Desktop и др.).
McpServer createMcpServer(Config config, ApiClient api) {
  final logger = Logger('McpServer');

  // Создаём MCP-сервер с объявлением capabilities
  final server = McpServer(
    Implementation(
      name: config.serverName,
      version: config.serverVersion,
    ),
    options: McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  // Регистрируем tools для задач
  logger.info('Registering tasks tools...');
  registerTasksTools(server, api);

  // Регистрируем tools для планов
  logger.info('Registering plans tools...');
  registerPlansTools(server, api);

  // Регистрируем tool для времени
  logger.info('Registering time tools...');
  registerTimeTools(server, api);

  logger.info('✓ All tools registered successfully');
  logger.info('  - Tasks: list_tasks, create_task, update_task, delete_task');
  logger.info('  - Plans: get_today_plan, generate_plan, get_plan_stats, update_plan_item');
  logger.info('  - Time: get_current_time');

  return server;
}
