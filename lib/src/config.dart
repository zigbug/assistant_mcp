import 'dart:io';

import 'package:dotenv/dotenv.dart';

/// Конфигурация MCP-сервера.
///
/// Загружает настройки с приоритетом: переменные окружения > .env файл > дефолты.
///
/// В локальной разработке сервер запускается без .env — используются дефолты,
/// совместимые с локальным бэкендом (localhost:8081, dev-ключ).
/// В продакшене (Docker / VPS) значения задаются через env-переменные.
class Config {
  /// URL бэкенда (без trailing slash)
  final String backendUrl;

  /// API-ключ для аутентификации на бэкенде
  final String apiKey;

  /// Имя MCP-сервера (сообщается клиентам через MCP-протокол)
  final String serverName;

  /// Версия MCP-сервера (сообщается клиентам)
  final String serverVersion;

  Config._({
    required this.backendUrl,
    required this.apiKey,
    required this.serverName,
    required this.serverVersion,
  });

  /// Загружает конфигурацию с учётом приоритетов:
  /// переменные окружения > .env файл > дефолты для локальной разработки.
  factory Config.load() {
    final env = DotEnv(includePlatformEnvironment: true);

    // Пытаемся загрузить .env файл, если он существует в рабочей директории
    final envFile = File('.env');
    if (envFile.existsSync()) {
      env.load(['.env']);
    }

    // Дефолты для локальной разработки — совместимы с `dart run bin/server.dart`
    // бэкенда из соседней директории assistant_backend.
    return Config._(
      backendUrl: env['BACKEND_URL'] ?? 'http://localhost:8081/api/v1',
      apiKey: env['API_KEY'] ?? 'dev-key-change-me-in-production',
      serverName: env['SERVER_NAME'] ?? 'assistant-mcp',
      serverVersion: env['SERVER_VERSION'] ?? '0.1.0',
    );
  }

  @override
  String toString() {
    return 'Config(backendUrl: $backendUrl, serverName: $serverName, '
        'serverVersion: $serverVersion, apiKey: ${'*' * apiKey.length})';
  }
}
