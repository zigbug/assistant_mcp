# Assistant MCP Server

MCP-сервер для AI-ассистента. Предоставляет tools для управления задачами, проектами, событиями и планами на день.

## Архитектура

### Режим stdio (локальный):
```
┌─────────────────┐
│  MCP Client     │ ← Qwen Desktop, Claude Desktop, etc.
│  (запускает процесс)│
└────────┬────────┘
         │ stdin/stdout (JSON-RPC)
         ▼
┌─────────────────┐
│  MCP Server     │ ← Этот проект (Dart)
│  (assistant_mcp)│
└────────┬────────┘
         │ HTTP REST API
         ▼
┌─────────────────┐
│  Backend API    │ ← assistant_backend
└─────────────────┘
```

### Режим HTTP (для Qwen Desktop и VPS):
```
┌─────────────────┐
│  Qwen Desktop   │ ← AI-модель (MCP-клиент)
│  (MCP Client)   │
└────────┬────────┘
         │ Streamable HTTP (POST /mcp + SSE GET /mcp)
         ▼
┌─────────────────┐
│  MCP Server     │ ← Этот проект (Dart)
│  (:8082/mcp)    │
└────────┬────────┘
         │ HTTP REST API
         ▼
┌─────────────────┐
│  Backend API    │ ← assistant_backend
└─────────────────┘
```

## Возможности (Tools)

### Tasks (Задачи)

- **`list_tasks`** — Получить список задач с фильтрами (по статусу, проекту, просроченные, запланированные на дату)
- **`create_task`** — Создать новую задачу
- **`update_task`** — Обновить существующую задачу
- **`delete_task`** — Удалить задачу (destructive)

### Plans (Планы на день)

- **`get_today_plan`** — Получить план на сегодня
- **`generate_plan`** — Сгенерировать план на указанную дату
- **`get_plan_stats`** — Получить статистику по плану (% выполнения, время)
- **`update_plan_item`** — Обновить элемент плана (статус, reschedule, заметка)

## Установка

### Требования

- Dart SDK >= 3.11.5
- Запущенный бэкенд `assistant_backend` на `http://localhost:8081`

### Шаги

1. **Клонируйте репозиторий:**
   ```bash
   git clone <repo-url>
   cd assistant_mcp
   ```

2. **Установите зависимости:**
   ```bash
   dart pub get
   ```

3. **Настройте конфигурацию:**
   
   Скопируйте `.env.example` в `.env` и отредактируйте:
   ```bash
   cp .env.example .env
   ```
   
   Отредактируйте `.env`:
   ```env
   BACKEND_URL=http://localhost:8081/api/v1
   API_KEY=your-super-secret-api-key-123
   SERVER_NAME=assistant-mcp
   SERVER_VERSION=0.1.0
   ```

4. **Запустите сервер:**
   
   **Режим stdio (по умолчанию):**
   ```bash
   dart run bin/assistant_mcp.dart
   ```
   
   **Режим HTTP (для Qwen Desktop и будущего VPS):**
   ```bash
   dart run bin/assistant_mcp.dart --transport=http
   ```
   
   По умолчанию HTTP-сервер слушает на порту 8082. Можно указать свой порт:
   ```bash
   dart run bin/assistant_mcp.dart --transport=http --port=9090
   ```
   
   Или через переменную окружения:
   ```bash
   export MCP_PORT=9090
   dart run bin/assistant_mcp.dart --transport=http
   ```
   
   Для stdio-режима вы увидите:
   ```
   ============================================================
     Assistant MCP Server is running!
     Transport: stdio (stdin/stdout)
     Backend: http://localhost:8081/api/v1
     Tools: 8 (4 tasks + 4 plans)
   ============================================================
   ```
   
   Для HTTP-режима:
   ```
   ============================================================
     Assistant MCP Server is running!
     Transport: Streamable HTTP
     URL: http://localhost:8082/mcp
     Backend: http://localhost:8081/api/v1
     Tools: 8 (4 tasks + 4 plans)
   ============================================================
   ```

## Подключение к Qwen Desktop

### Вариант 1: Streamable HTTP (рекомендуется)

1. Запустите MCP-сервер в HTTP-режиме:
   ```bash
   dart run bin/assistant_mcp.dart --transport=http
   ```

2. Откройте настройки Qwen Desktop
3. Перейдите в раздел **MCP Servers**
4. Добавьте новый сервер:
   - **Имя:** `assistant`
   - **Описание:** `Личный ассистент: задачи, проекты, планы дня`
   - **Тип:** `StreamableHTTP`
   - **URL:** `http://localhost:8082/mcp`

5. Нажмите **Сохранить и включить**
6. Проверьте, что сервер появился в списке и имеет статус "подключен"

### Вариант 2: STDIO

Если Qwen Desktop поддерживает запуск произвольных команд через stdio:

1. Откройте настройки Qwen Desktop
2. Перейдите в раздел **MCP Servers**
3. Добавьте новый сервер:
   ```json
   {
     "mcpServers": {
       "assistant": {
         "command": "dart",
         "args": ["run", "D:/vibe_projects/assistant_mcp/bin/assistant_mcp.dart"],
         "cwd": "D:/vibe_projects/assistant_mcp"
       }
     }
   }
   ```
4. Перезапустите Qwen Desktop
5. Проверьте, что сервер появился в списке доступных MCP-серверов

## Использование

После подключения к Qwen Desktop вы можете использовать естественный язык:

- "Покажи мои задачи на сегодня"
- "Создай задачу: Изучить MCP протокол с важностью 4"
- "Сгенерируй план на завтра"
- "Отметь задачу 1 как выполненную"
- "Покажи статистику по сегодняшнему плану"

## Разработка

### Структура проекта

```
assistant_mcp/
├── bin/
│   └── assistant_mcp.dart          # Точка входа
├── lib/
│   ├── assistant_mcp.dart          # Публичное API
│   └── src/
│       ├── config.dart             # Конфигурация
│       ├── api_client.dart         # HTTP-клиент
│       ├── server.dart             # Создание MCP-сервера
│       └── tools/
│           ├── tasks_tools.dart    # Tools для задач
│           └── plans_tools.dart    # Tools для планов
├── test/
│   └── assistant_mcp_test.dart     # Тесты
├── .env                            # Локальная конфигурация
├── .env.example                    # Шаблон конфигурации
└── pubspec.yaml                    # Зависимости
```

### Добавление новых tools

1. Создайте файл в `lib/src/tools/` (например, `projects_tools.dart`)
2. Реализуйте функцию `registerProjectsTools(McpServer server, ApiClient api)`
3. Используйте `server.registerTool()` для регистрации каждого tool
4. Импортируйте и вызовите функцию в `lib/src/server.dart`

Пример:
```dart
void registerProjectsTools(McpServer server, ApiClient api) {
  server.registerTool(
    'list_projects',
    description: 'Получить список проектов',
    inputSchema: JsonSchema.object(),
    callback: (args, extra) async {
      final projects = await api.get('/projects');
      return CallToolResult(
        content: [TextContent(text: jsonEncode(projects))],
      );
    },
  );
}
```

## Технологии

- **Dart SDK** 3.11.5+
- **mcp_dart** 2.4.1 — MCP SDK с поддержкой MCP 2026-07-28
- **http** 1.2.0 — HTTP-клиент
- **dotenv** 4.2.0 — Конфигурация из .env
- **logging** 1.3.0 — Логирование

## Лицензия

MIT

## Автор

Денис (Senior Flutter/Golang Developer)
