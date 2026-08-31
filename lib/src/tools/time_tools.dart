import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import '../api_client.dart';

/// Регистрирует tool для получения текущего времени с бэкенда.
///
/// Tools:
/// - `get_current_time` — текущее время и часовой пояс (для ИИ)
void registerTimeTools(McpServer server, ApiClient api) {
  final logger = Logger('TimeTools');

  server.registerTool(
    'get_current_time',
    description: 'Получить текущее время и часовой пояс. Возвращает '
        'время по UTC и локальное время бэкенда, часовой пояс и смещение. '
        'Используйте для определения текущего момента времени.',
    inputSchema: JsonSchema.object(),
    callback: (args, extra) async {
      try {
        logger.info('get_current_time called');

        final time = await api.get('/time');

        if (time == null || time is! Map || time.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Не удалось получить время.')],
          );
        }

        final buffer = StringBuffer('🕒 Текущее время:\n\n');
        buffer.writeln('UTC: ${time['serverTimeUtc']}');
        if (time['serverTimeLocal'] != null) {
          buffer.writeln('Локальное: ${time['serverTimeLocal']}');
        }
        if (time['timezone'] != null) {
          buffer.writeln('Часовой пояс: ${time['timezone']}');
        }
        if (time['utcOffsetMinutes'] != null) {
          final offset = time['utcOffsetMinutes'] as num;
          final sign = offset >= 0 ? '+' : '-';
          final abs = offset.abs();
          final hours = abs ~/ 60;
          final minutes = abs % 60;
          buffer.writeln(
              'Смещение: $sign${hours.toString().padLeft(2, '0')}:'
              '${minutes.toString().padLeft(2, '0')} '
              '($offset мин)');
        }

        return CallToolResult(
          content: [TextContent(text: buffer.toString())],
        );
      } catch (e) {
        logger.severe('Error in get_current_time: $e');
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Ошибка при получении времени: $e')],
        );
      }
    },
  );
}
