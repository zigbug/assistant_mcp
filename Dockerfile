# Используем полноценный Dart SDK для надежности
FROM dart:stable

WORKDIR /app

# 1. Копируем манифесты и получаем зависимости
COPY pubspec.* ./
RUN dart pub get

# 2. Копируем исходный код
COPY . .

# 3. Создаем пользователя для безопасности
RUN useradd -r -u 10001 appuser && \
    chown -R appuser:appuser /app

USER appuser
EXPOSE 8082

# 4. Запускаем MCP-сервер в HTTP-режиме
ENTRYPOINT ["dart", "run", "bin/assistant_mcp.dart", "--transport=http"]