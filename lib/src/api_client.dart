import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'config.dart';

/// HTTP-клиент для взаимодействия с бэкендом assistant_backend.
///
/// Все методы возвращают распарсенный JSON. При ошибке HTTP (4xx, 5xx)
/// выбрасывает [ApiException] с деталями ошибки.
class ApiClient {
  final Config _config;
  final http.Client _httpClient;
  final Logger _logger = Logger('ApiClient');

  ApiClient(this._config) : _httpClient = http.Client();

  /// GET запрос к бэкенду.
  ///
  /// [endpoint] — путь без базового URL (например, '/tasks').
  /// [queryParams] — опциональные query-параметры.
  Future<dynamic> get(
    String endpoint, [
    Map<String, String>? queryParams,
  ]) async {
    final uri = Uri.parse(
      '${_config.backendUrl}$endpoint',
    ).replace(queryParameters: queryParams);

    _logger.fine('GET $uri');

    final response = await _httpClient.get(
      uri,
      headers: {'x-api-key': _config.apiKey, 'Accept': 'application/json'},
    );

    return _handleResponse(response);
  }

  /// POST запрос к бэкенду.
  ///
  /// [endpoint] — путь без базового URL.
  /// [body] — тело запроса (будет сериализовано в JSON).
  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('${_config.backendUrl}$endpoint');

    _logger.fine('POST $uri');
    _logger.finest('Body: $body');

    final response = await _httpClient.post(
      uri,
      headers: {
        'x-api-key': _config.apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    return _handleResponse(response);
  }

  /// PATCH запрос к бэкенду.
  ///
  /// [endpoint] — путь без базового URL.
  /// [body] — тело запроса (будет сериализовано в JSON).
  Future<dynamic> patch(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('${_config.backendUrl}$endpoint');

    _logger.fine('PATCH $uri');
    _logger.finest('Body: $body');

    final response = await _httpClient.patch(
      uri,
      headers: {
        'x-api-key': _config.apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    return _handleResponse(response);
  }

  /// DELETE запрос к бэкенду.
  ///
  /// [endpoint] — путь без базового URL.
  Future<void> delete(String endpoint) async {
    final uri = Uri.parse('${_config.backendUrl}$endpoint');

    _logger.fine('DELETE $uri');

    final response = await _httpClient.delete(
      uri,
      headers: {'x-api-key': _config.apiKey, 'Accept': 'application/json'},
    );

    // Для DELETE 204 No Content — это успех
    if (response.statusCode == 204) {
      return;
    }

    _handleResponse(response);
  }

  /// Проверяет, что бэкенд доступен (health check).
  ///
  /// Возвращает true, если бэкенд отвечает.
  Future<bool> checkHealth() async {
    try {
      // Health check endpoint не требует API-ключа
      final uri = Uri.parse(
        _config.backendUrl.replaceAll('/api/v1', '/health'),
      );
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      _logger.warning('Health check failed: $e');
      return false;
    }
  }

  /// Обрабатывает HTTP-ответ.
  ///
  /// Если статус 2xx — возвращает распарсенный JSON (или null для пустого тела).
  /// Если статус 4xx/5xx — выбрасывает [ApiException].
  dynamic _handleResponse(http.Response response) {
    _logger.fine('Response: ${response.statusCode}');

    // Успешные статусы
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return null;
      }
      try {
        return jsonDecode(response.body);
      } catch (e) {
        throw ApiException(
          statusCode: response.statusCode,
          message: 'Invalid JSON in response',
          body: response.body,
        );
      }
    }

    // Ошибки
    String errorMessage = 'HTTP ${response.statusCode}';
    try {
      final errorBody = jsonDecode(response.body);
      if (errorBody is Map && errorBody['error'] != null) {
        errorMessage = errorBody['error'].toString();
      }
    } catch (_) {
      // Если не удалось распарсить, используем дефолтное сообщение
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: errorMessage,
      body: response.body,
    );
  }

  /// Закрывает HTTP-клиент.
  void close() {
    _httpClient.close();
  }
}

/// Исключение, выбрасываемое при ошибках API.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? body;

  ApiException({required this.statusCode, required this.message, this.body});

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, message: $message)';
}
