import 'dart:io';
import 'package:dotenv/dotenv.dart';

/// Конфигурация MCP-сервера.
///
/// Загружает настройки из .env файла или переменных окружения.
/// Приоритет: переменные окружения > .env файл > дефолтные значения.
class Config {
  /// URL бэкенда (без trailing slash)
  final String backendUrl;

  /// API-ключ для аутентификации на бэкенде
  final String apiKey;

  /// Имя MCP-сервера
  final String serverName;

  /// Версия MCP-сервера
  final String serverVersion;

  Config._({
    required this.backendUrl,
    required this.apiKey,
    required this.serverName,
    required this.serverVersion,
  });

  /// Загружает конфигурацию из .env файла и переменных окружения.
  ///
  /// Выбрасывает [StateError], если обязательные настройки отсутствуют.
  factory Config.load() {
    final env = DotEnv(includePlatformEnvironment: true);

    // Пытаемся загрузить .env файл, если он существует
    final envFile = File('.env');
    if (envFile.existsSync()) {
      env.load(['.env']);
    }

    final backendUrl = env['BACKEND_URL'];
    if (backendUrl == null || backendUrl.isEmpty) {
      throw StateError(
        'BACKEND_URL is required. Set it in .env or environment variable.',
      );
    }

    final apiKey = env['API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        'API_KEY is required. Set it in .env or environment variable.',
      );
    }

    return Config._(
      backendUrl: backendUrl,
      apiKey: apiKey,
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
