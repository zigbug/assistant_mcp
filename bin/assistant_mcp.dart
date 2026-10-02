import 'dart:io';

import 'package:assistant_mcp/assistant_mcp.dart';
import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

/// Точка входа MCP-сервера.
///
/// Загружает конфигурацию, создаёт API-клиент и MCP-сервер,
/// затем запускает сервер в одном из двух режимов:
///   - `stdio` (по умолчанию) — для локальных MCP-клиентов, которые сами
///     запускают процесс (Claude Desktop и т.п.).
///   - `http` — Streamable HTTP, для Qwen Desktop и будущего деплоя на VPS.
///
/// Примеры запуска:
///   dart run bin/assistant_mcp.dart                      # stdio
///   dart run bin/assistant_mcp.dart --transport=http     # HTTP на :8082
///   dart run bin/assistant_mcp.dart --transport=http --port=9090
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
      logger.warning(
        '  MCP server will start, but tools may fail until backend is available.',
      );
    }

    // === Выбор транспорта ===
    final transportType = _argValue(arguments, '--transport') ?? 'stdio';
    final port =
        int.tryParse(
          _argValue(arguments, '--port') ??
              Platform.environment['MCP_PORT'] ??
              '',
        ) ??
        8082;

    switch (transportType) {
      case 'http':
        final host = Platform.environment['MCP_HOST'] ?? 'localhost';
        final allowedHosts =
            (Platform.environment['MCP_ALLOWED_HOSTS'] ?? 'localhost,127.0.0.1')
                .split(',')
                .map((h) => h.trim())
                .where((h) => h.isNotEmpty)
                .toSet();
        await _startHttpServer(config, api, host, allowedHosts, port, logger);
        break;
      case 'stdio':
      default:
        await _startStdioTransport(config, api, logger);
        break;
    }
  } catch (e, stackTrace) {
    stderr.writeln('Fatal error: $e');
    stderr.writeln(stackTrace);
    exit(1);
  }
}

/// Запуск MCP-сервера через Streamable HTTP.
///
/// Поднимает HTTP-сервер на указанном порту, принимает MCP JSON-RPC
/// сообщения через POST /mcp и отдаёт события через SSE GET /mcp.
/// Подходит для Qwen Desktop и для деплоя на VPS (Docker).
///
/// [host] — интерфейс привязки: `localhost` локально, `0.0.0.0` в Docker,
/// чтобы сервер был доступен через опубликованный порт.
///
/// [allowedHosts] — белый список заголовка Host для защиты от DNS-rebinding.
/// В Docker/за reverse-proxy добавьте сюда домен, с которым ходят клиенты
/// (например, assistant.example.com).
Future<void> _startHttpServer(
  Config config,
  ApiClient api,
  String host,
  Set<String> allowedHosts,
  int port,
  Logger logger,
) async {
  // StreamableMcpServer автоматически:
  //  - создаёт HTTP-сервер (HttpServer.bind)
  //  - роутит POST/GET запросы на /mcp
  //  - создаёт отдельный McpServer для каждой сессии через serverFactory
  //  - обрабатывает stateless-режим MCP 2026-07-28 и legacy-сессии MCP 2025-11-25
  final httpServer = StreamableMcpServer(
    serverFactory: (connectionId) => createMcpServer(config, api),
    host: host,
    port: port,
    path: '/mcp',
    // Включаем защиту от DNS-rebinding: принимаем запросы только
    // с разрешёнными Host-заголовками.
    enableDnsRebindingProtection: true,
    allowedHosts: allowedHosts,
  );

  await httpServer.start();

  logger.info('✓ HTTP MCP server started on $host:$port');

  // В HTTP-режиме stdout свободен — можно печатать баннер в stdout
  // (в отличие от stdio, где stdout занят JSON-RPC протоколом).
  stdout.writeln('');
  stdout.writeln('=' * 60);
  stdout.writeln('  Assistant MCP Server is running!');
  stdout.writeln('  Transport: Streamable HTTP');
  stdout.writeln('  URL: http://$host:$port/mcp');
  stdout.writeln('  Allowed hosts: ${allowedHosts.join(', ')}');
  stdout.writeln('  Backend: ${config.backendUrl}');
  stdout.writeln('  Tools: 14 (4 tasks + 5 plans + 4 events + 1 time)');
  stdout.writeln('=' * 60);
  stdout.writeln('');
}

/// Запуск MCP-сервера через stdio (stdin/stdout).
///
/// Подходит для локальных MCP-клиентов, которые запускают процесс сами
/// и общаются через stdin/stdout в формате JSON-RPC.
///
/// ВАЖНО: в этом режиме stdout ЗАРЕЗЕРВИРОВАН под MCP-протокол.
/// Никаких print() в stdout — только логи в stderr через logger!
Future<void> _startStdioTransport(
  Config config,
  ApiClient api,
  Logger logger,
) async {
  final server = createMcpServer(config, api);

  // Подключаем транспорт. После connect() сервер начинает слушать stdin
  // и писать JSON-RPC ответы в stdout.
  final transport = StdioServerTransport();
  await server.connect(transport);

  // Логируем в stderr — stdout уже занят JSON-RPC.
  logger.info('✓ MCP server connected via stdio transport');
}

/// Извлекает значение аргумента командной строки.
///
/// Поддерживает оба формата:
///   --name value
///   --name=value
String? _argValue(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == name && i + 1 < args.length) return args[i + 1];
    if (args[i].startsWith('$name=')) return args[i].substring(name.length + 1);
  }
  return null;
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
