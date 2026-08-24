import 'dart:io';

import 'package:assistant_mcp/assistant_mcp.dart';
import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

/// Точка входа MCP-сервера.
///
/// Загружает конфигурацию, создаёт API-клиент и MCP-сервер,
/// затем запускает сервер в stdio-режиме.
void main(List<String> arguments) async {
  // Настраиваем логирование
  _setupLogging();

  final logger = Logger('Main');
  logger.info('Starting Assistant MCP Server...');

  try {
    // Загружаем конфигурацию
    final config = Config.load();
    logger.info('Configuration loaded: $config');

    // Создаём API-клиент
    final api = ApiClient(config);

    // Проверяем доступность бэкенда
    logger.info('Checking backend availability...');
    final isHealthy = await api.checkHealth();
    if (isHealthy) {
      logger.info('✓ Backend is reachable');
    } else {
      logger.warning('⚠ Backend is not reachable at ${config.backendUrl}');
      logger.warning('  MCP server will start, but tools may fail until backend is available.');
    }

    // Создаём MCP-сервер
    final server = createMcpServer(config, api);
    logger.info('✓ MCP server created with all tools');

    // Выводим информацию о запуске
    print('');
    print('=' * 60);
    print('  Assistant MCP Server is running!');
    print('  Transport: stdio (stdin/stdout)');
    print('  Backend: ${config.backendUrl}');
    print('  Tools: 8 (4 tasks + 4 plans)');
    print('=' * 60);
    print('');

    // Запускаем сервер с stdio транспортом
    // stdout используется для MCP protocol messages
    // stderr используется для логов
    final transport = StdioServerTransport();
    await server.connect(transport);
  } catch (e, stackTrace) {
    stderr.writeln('Fatal error: $e');
    stderr.writeln(stackTrace);
    exit(1);
  }
}

/// Настраивает логирование.
///
/// Для stdio-сервера важно, чтобы логи шли в stderr,
/// а не в stdout (stdout зарезервирован для MCP protocol messages).
void _setupLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    stderr.writeln(
      '[${record.time.toIso8601String()}] '
      '${record.level.name.padRight(7)} '
      '${record.loggerName}: '
      '${record.message}',
    );
    if (record.error != null) {
      stderr.writeln('  Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      stderr.writeln('  StackTrace: ${record.stackTrace}');
    }
  });
}
