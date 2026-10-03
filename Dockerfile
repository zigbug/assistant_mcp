# =============================================================================
# Assistant MCP Server — production image
#
# Multi-stage build:
#   1. builder: фиксированный Dart SDK, зависимости строго по pubspec.lock,
#      AOT-компиляция в нативный бинарник. Ошибки компиляции (типа
#      "Undefined name 'JsonSchema'") проявляются ЗДЕСЬ, при `docker build`,
#      а не краш-лупом в рантайме.
#   2. runtime: минимальный debian-slim + готовый бинарник, non-root.
#
# Сборка:  docker compose -f docker-compose.prod.yml build --no-cache
# Запуск:  docker compose -f docker-compose.prod.yml up -d
# =============================================================================

# --- Stage 1: сборка ---------------------------------------------------------
# Тег зафиксирован (не :stable), чтобы локально и на сервере был один SDK.
FROM dart:3.11.5 AS builder

WORKDIR /app

# 1. Манифесты отдельно — слой с зависимостями кешируется,
#    пока не изменятся pubspec.yaml / pubspec.lock.
COPY pubspec.yaml pubspec.lock ./

# --enforce-lockfile: версии берутся ТОЛЬКО из lock-файла.
# Если lock разойдётся с yaml — сборка упадёт сразу и явно.
RUN dart pub get --enforce-lockfile

# 2. Исходники и компиляция в AOT-бинарник.
COPY . .
RUN dart compile exe bin/assistant_mcp.dart -o /app/assistant_mcp

# --- Stage 2: runtime --------------------------------------------------------
FROM debian:bookworm-slim

# CA-сертификаты для HTTPS-запросов к бэкенду.
#
# tzdata обязателен: MCP форматирует даты в локальной зоне процесса, а
# `debian:bookworm-slim` без неё откатывается на UTC. Тогда «локальная полночь»
# плана (например 02.10 = 01.10T21:00Z) отрисовалась бы предыдущим днём.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

ENV TZ=Europe/Moscow

# Непривилегированный пользователь.
RUN useradd --system --uid 10001 appuser

WORKDIR /app
COPY --from=builder --chown=appuser:appuser /app/assistant_mcp /app/assistant_mcp

USER appuser
EXPOSE 8082

# Переменные окружения читаются из docker-compose (.env):
#   BACKEND_URL, API_KEY, MCP_PORT, MCP_HOST, MCP_ALLOWED_HOSTS
ENTRYPOINT ["/app/assistant_mcp", "--transport=http"]
