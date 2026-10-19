# Local Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Получить Flutter приложение с рабочим локальным списком дел, повторами, двумя темами и сохранением без сети.

**Architecture:** Чистая доменная модель задаёт задачи и команды. Drift хранит каноническое состояние, локальную очередь и её видимую проекцию; ChangeNotifier обновляет главный экран. Экспорт и импорт используют ту же репозиторную границу.

**Tech Stack:** Flutter stable, Dart, Drift NativeDatabase в background isolate, path_provider, path, uuid, timezone, file_picker; flutter_test и integration_test.

**Spec:** [Спецификация](../specs/2026-10-18-everyday-todo-design.md), [общий план](2026-10-19-everyday-todo-plan.md).

## Global Constraints

- Применяются Global Constraints общего плана; один главный экран, русский текст, светлая и тёмная темы.
- Название 1…500 Unicode code points, заметка до 10000; календарная дата YYYY-MM-DD не является моментом UTC.
- Функции Today, All, свои списки, поиск, заметки, повтор, dueDate и reminderAtUtc независимы.
- Обычная строка 60–72, интерактивная область не меньше 48; sidebar 216 начиная с ширины 900.
- Нет сетевых ожиданий в пути локального создания и выполнения задачи.
- Клиентские build и тесты запускаются из app/. Версии зависимостей фиксируются pubspec.lock.

## Review Focus

- B1: emoji и кириллица не ломают валидацию и сериализацию.
- B2: закрытие БД после записи задачи, но до отправки, сохраняет задачу и операцию вместе.
- B3: экран 360 с открытой клавиатурой и крупным текстом остаётся пригодным для ввода.
- B3: 1000 задач и длинные названия не приводят к переполнению или построению всех строк сразу.
- B4: некорректный JSON и отмена системного диалога не меняют пользовательские данные.

## Task B1: Подготовить Flutter и общую доменную модель

**Files:** Create `tools/setup-dev.ps1`, `docs/development.md`, `app/` через `flutter create --platforms=windows,android --project-name day_planner app`; затем create `app/lib/domain/{models,commands,validation,recurrence}.dart`, `app/lib/sync/protocol.dart`, `app/test/domain/{validation,recurrence,serialization}_test.dart`. Modify `app/pubspec.yaml` и `.gitignore`.

**Interfaces:**
- Produces immutable `TaskItem`, `TaskList`, `RecurrenceRule`, `LocalDate`, `TaskQuery`, `CommandReceipt` и sealed `TaskCommand`.
- `LocalDate.parse(String)`, `LocalDate.toString()`, `compareTo(LocalDate)`; только валидная календарная дата.
- `normalizeTitle(String):String`, `validateNote(String):String`, `nextOccurrence(RecurrenceRule,LocalDate?,LocalDate):LocalDate`, `successorId(String,LocalDate):String`.
- DTO `SyncRequest`, `Operation`, `SyncResponse`, `Acknowledgement`, `EntityChange` имеют `fromJson(Map<String,Object?>)` и `toJson()` по A1.
- TaskCommand имеет варианты createTask, patchTask, completeTask, undoCompletion, deleteTask, restoreTask, createList, patchList, deleteList, upsertRule, reorderTask, importEntity. Параметры — поля моделей и id; completedAt и successorId нельзя менять через patchTask. importEntity используется только после подтверждённого preview B4 и порождает restore со snapshot по общему протоколу.
- TaskQuery содержит `view:today|all|list`, `listId?`, `today:LocalDate`, `search:String`, `includeCompleted:bool`.
- CommandReceipt содержит operationId, completionId? и provisionalSuccessorId?.

- [ ] **Step 1: Настроить исполняемые инструменты и сгенерировать проект только двух нужных платформ.** Проверить существующий Flutter до скачивания. Если отсутствует, использовать официальный stable архив, проверить его SHA256 и распаковать в игнорируемый `.tools/flutter` проекта. PUB_CACHE и Gradle cache разместить в игнорируемом локальном каталоге или разрешённом runtime, пути документировать без глобального изменения PATH. Проверить `flutter --version` и `flutter doctor -v`. Android SDK/JDK подготовить из официальных источников; если принятие лицензии или системная настройка требует человека, предоставить точный шаг, продолжая независимые задачи. Версии и фактические отсутствующие компоненты записать в development.md.
- [ ] **Step 2: После доступности SDK записать падающие доменные тесты.**

```dart
expect(normalizeTitle('  Молоко 🥛  '), 'Молоко 🥛');
expect(normalizeTitle(List.filled(500, '😀').join()).runes.length, 500);
expect(() => normalizeTitle(List.filled(501, '😀').join()), throwsFormatException);
expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
expect(nextOccurrence(monthly31, LocalDate.parse('2026-01-31'),
  LocalDate.parse('2026-01-31')).toString(), '2026-02-28');
```

`monthly31` берётся из общего recurrence.json. Тесты обходят все fixtures A1, проверяют round trip каждого DTO и nullable полей.

- [ ] **Step 3: Выполнить `flutter test test/domain`; получить FAIL до реализации.**
- [ ] **Step 4: Реализовать перечисленные модели и чистые функции.** Для дат использовать календарную арифметику, не прибавление 24 часов к локальному timestamp. Подключить timezone, uuid и flutter_localizations; не вводить генераторы immutable моделей и отдельный state framework.
- [ ] **Step 5: `flutter test test/domain` и `flutter analyze` проходят; `flutter build windows --debug` проверяет runner, Android build выполняется при доступном SDK.** Недоступная Android сборка остаётся отдельной непроверенной строкой, без фиктивного PASS.
- [ ] **Step 6: Коммит `feat: establish native client and task domain`.**

## Task B2: Локальная БД, атомарные команды и очередь

**Files:** Create `app/lib/data/{tables,app_database,task_repository}.dart`, `app/test/data/{task_repository,migration}_test.dart`, `app/test/helpers.dart`. Modify `app/pubspec.yaml` для drift, drift_dev, build_runner, sqlite3 и path_provider.

**Interfaces:**
- Consumes модели, команды и SyncResponse B1.
- Produces `AppDatabase.open(File file,{required String workspaceId})`, `AppDatabase.memory({required String workspaceId})`, `close():Future<void>`.
- Produces `SqliteTaskRepository(AppDatabase db,{required DateTime Function() clock,required String Function() newId})`.
- Абстрактный `TaskRepository` задаёт интерфейс, `SqliteTaskRepository` его реализует: `watchTasks(TaskQuery):Stream<List<TaskItem>>`, `watchLists():Stream<List<TaskList>>`, `execute(TaskCommand):Future<CommandReceipt>`, `pendingBatch({required int maxOperations,required int byteBudget}):Future<List<Operation>>`, `applySyncResponse(SyncResponse):Future<void>`, `getCursor():Future<int>`, `markRejected(String operationId,String code):Future<void>`, `readTask(String id):Future<TaskItem?>`.
- Таблицы: canonicalEntities, pendingOperations, projectedTasks, projectedLists, recurrenceRules, completionLinks, localSettings и syncMetadata. Проекция пересобирается только для затронутых сущностей после изменения base или очереди.

- [ ] **Step 1: Записать persistence и конфликтные тесты.**

```dart
await repository.execute(TaskCommand.createTask(id: taskId, title: 'Хлеб', listId: inboxId));
await database.close();
// Открыть тот же временный файл и создать новый repository.
expect((await reopened.readTask(taskId))!.title, 'Хлеб');
expect((await reopened.pendingBatch(maxOperations:100, byteBudget:260000)).length, 1);
await reopened.applySyncResponse(remoteTitleChangeWithoutLocalAck);
expect((await reopened.readTask(taskId))!.title, 'Хлеб');
```

Второй сценарий использует локальную неподтверждённую правку и входящий старый title. Добавить fault injection перед commit, удаление списка, отмену удаления, stable order при совпадении position, отбор overdue/today и повтор после завершения. Тесты миграции открывают файл предыдущей версии и сохраняют очередь.

- [ ] **Step 2: `flutter test test/data` падает на отсутствующей реализации.**
- [ ] **Step 3: Реализовать репозиторий с NativeDatabase.createInBackground для файловой БД.** Команда, optimistic projection и outbox фиксируются одной транзакцией. Входящий ответ, подтверждения и cursor также атомарны. Для предварительного потомка хранить completionLinks и зависимости; не отправлять самостоятельное createTask этого потомка. Порядок в пределах группы по position затем id.
- [ ] **Step 4: `dart run build_runner build --delete-conflicting-outputs`, затем `flutter test test/data test/domain`; все сценарии проходят.** Генерация обновляет только производные Dart файлы проекта.
- [ ] **Step 5: Коммит `feat: persist tasks and atomic offline operations`.**

## Task B3: Главный экран и редактирование

**Files:** Create `app/lib/features/tasks/{task_controller,task_home,task_row,task_composer,task_detail_panel,list_panel}.dart`, `app/lib/theme/{app_theme,motion_tokens}.dart`, `app/lib/platform/feedback_service.dart`, `app/test/features/{task_home,task_keyboard,task_layout}_test.dart`. Modify `app/lib/{main,app}.dart`.

**Interfaces:**
- Consumes TaskRepository B2 и TaskQuery B1.
- Produces `TaskController(TaskRepository,{required CompletionFeedback feedback,required LocalDate Function() today}) extends ChangeNotifier` с `setQuery`, `addTask`, `patchTask`, `completeTask`, `undoCompletion`, `deleteTask`, `restoreTask`, `saveList`, `deleteList`, `reorderTask` и `dispose`. Изменяющие методы возвращают Future<CommandReceipt>; setQuery возвращает void.
- `CompletionFeedback.onUserCompletion({required bool undo}):Future<void>` — небольшой порт для последующего подключения C3; тихая реализация допустима только на этом промежуточном этапе и в тестах.
- `TaskHome({required TaskController controller})`, `TaskRow`, `TaskComposer`, `TaskDetailPanel`, `ListPanel` — UI без SQL и HTTP.

- [ ] **Step 1: Записать widget сценарии.**

```dart
await tester.enterText(find.byKey(const Key('task-title-input')), 'Записаться к врачу');
await tester.testTextInput.receiveAction(TextInputAction.done);
await tester.pump();
expect(find.text('Записаться к врачу'), findsOneWidget);
expect(fakeRepository.createdTasks.single.title, 'Записаться к врачу');
```

fakeRepository реализует публичный интерфейс B2 только для widget тестов. Проверить Ctrl+N, Ctrl+F, Escape, фокус Tab, поиск в note, собственные списки и Today/All. При 360×800, textScale 1.5 и viewInsets.bottom=300 `tester.takeException()` возвращает null. На 760 sidebar скрыт, на 1024 sidebar шириной 216; при 1440 подробности могут показываться рядом. Тысяча задач проверяется lazy builder, а не поиском тысячи одновременно построенных строк.

- [ ] **Step 2: `flutter test test/features` падает до создания экранов.**
- [ ] **Step 3: Реализовать UI и подключить файловый repository в main.** Перечитать docs/references и открыть изображения. Взять структуру REF-0547, мягкую палитру REF-0537 и малый эмоциональный акцент REF-0819. Заголовок задачи 16, secondary 12–13, header 28; sidebar 216 с breakpoint 900, details inline с 1280, иначе overlay. Minimum window 760×560 задаётся runner. Инпут всегда доступен над клавиатурой; сохранять его черновик при входящем обновлении, не сбрасывать ScrollController при открытии details.
- [ ] **Step 4: Запустить `flutter test test/features`, `flutter analyze` и Windows приложение.** Проверить длинное название, пустые состояния, создание и перезапуск с выключенной сетью. Реальные скриншоты сравнить с направлением референсов; результат записать в verification.md, не подменять его мокапом.
- [ ] **Step 5: Коммит `feat: build calm daily task interface`.**

## Task B4: Настройки и перенос данных

**Files:** Create `app/lib/data/backup_repository.dart`, `app/lib/features/settings/{settings_controller,settings_panel,import_preview}.dart`, `app/lib/platform/file_dialogs.dart`, `app/test/data/backup_repository_test.dart`, `app/test/features/settings_test.dart`. Modify `app/lib/app.dart`, `app/pubspec.yaml`, `docs/development.md`.

**Interfaces:**
- Consumes TaskRepository и DB B2.
- Produces `BackupRepository.exportBytes():Future<Uint8List>`, `inspectImport(Uint8List):Future<ImportPreview>`, `applyImport(ImportPreview):Future<ImportResult>`, `createSafetyBackup():Future<File>`.
- ImportPreview: parsed schemaVersion=1, newCount, matchingCount, validated entities и digest. ImportResult: appliedCount, safetyBackupPath. Применение проверяет digest и актуальное состояние, не доверяет UI счётчикам.
- `FileDialogs.saveJson(String filename,Uint8List bytes):Future<bool>`, `pickJson():Future<Uint8List?>` через file_picker; null/false означает отмену.
- `SettingsController` хранит themeMode, completionSoundEnabled, volume 0…1, hapticsEnabled в localSettings, не отправляет их в sync.

- [ ] **Step 1: Записать round trip и защиту данных.**

```dart
final preview = await backups.inspectImport(await backups.exportBytes());
expect(preview.newCount, 0);
expect(preview.matchingCount, currentEntityCount);
expect(utf8.decode(await backups.exportBytes()), isNot(contains(testSyncToken)));
expect(() => backups.inspectImport(Uint8List.fromList(utf8.encode('{broken'))), throwsFormatException);
```

Проверить неизвестную schemaVersion, неверную ссылку на правило, 501 code point в title, сохранение исходных записей при невалидном импорте, поведение отмены picker и отсутствие изменений до подтверждения preview. Экспорт и импорт завершённой повторяющейся задачи и её существующего потомка сохраняет оба id и не создаёт ещё один следующий экземпляр.

- [ ] **Step 2: `flutter test test/data/backup_repository_test.dart test/features/settings_test.dart` падает до реализации.**
- [ ] **Step 3: Реализовать экспорт без ключа, preview и атомарный импорт с предварительной копией.** По совпавшему id применять подтверждённый импортированный снимок, новые создавать; перед применением показать counts. Исторические completedAt и связи потомков сохранять снимком через importEntity/restore, не переигрывая complete с побочным созданием следующей задачи. Формат экспорта содержит эти связи в дополнение к полям задачи. Создавать реальные outbox операции в правильном порядке rule/list/task. Настройки сразу меняют тему; звук и вибрация фактически подключаются C3.
- [ ] **Step 4: Повторить тесты, выполнить полный `flutter test` и вручную сохранить/открыть JSON через нативный диалог.** Android пути не трактовать как обычный Windows filename; использовать bytes picker API. Совместимость saveFile на Android и Windows подтверждается [документацией file_picker](https://pub.dev/packages/file_picker).
- [ ] **Step 5: Коммит `feat: add local preferences and safe task backup`.**

## Результат этапа

Локальное приложение сохраняет настоящие данные и пригодно для проверки Windows интерфейса. Сетевое подключение, звук и уведомления ещё не объявляются готовыми: они являются результатом следующего этапа.
