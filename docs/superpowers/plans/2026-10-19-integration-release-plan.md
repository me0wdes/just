# Integration and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Подключить локальный клиент к сервису, добавить звук, движение и системные напоминания, собрать Windows и Android артефакты.

**Architecture:** SyncEngine обменивает постоянную outbox через транспортный порт и применяет ответы репозиторием. ConnectionService отдельно управляет адресом, ключом и выбором workspace. Платформенные сервисы выполняют напоминания и отклик без сетевой зависимости.

**Tech Stack:** Flutter, Dart HttpClient, node:test сервис A, Drift клиент B, flutter_secure_storage, flutter_local_notifications, timezone, audioplayers, msix, небольшой Android/Windows platform channel для проверки состояния звука.

**Spec:** [Спецификация](../specs/2026-10-18-everyday-todo-design.md), [общий план и протокол](2026-10-19-everyday-todo-plan.md).

## Global Constraints

- Используются готовые контракты A1, API сервиса A4 и репозиторий B2, без второго формата синхронизации.
- По 100 операций и не больше 256 КиБ на HTTP запрос; polling 15 секунд только при активном приложении; backoff 2…60 секунд.
- Ключ не в URL, Git, экспорте, скриншоте настроек или логе. Только HTTPS, кроме явно включённого debug loopback.
- Звук 80–140 мс только на явное действие текущего пользователя; удалённое выполнение не звучит.
- Повторы уведомлений реализуются одноразовым расписанием текущего экземпляра, не periodicallyShow на Windows.
- Сборки и проверка на устройствах — разные критерии; недоступный телефон или интернет сервер не помечаются PASS.

## Review Focus

- C1: потерянный HTTP ответ и повтор batch не дублируют эффект.
- C1: локальный черновик, зависимые операции и предварительный потомок не теряются от входящих изменений.
- C2: смена workspace с pending операциями требует backup и явно выбранного merge/openSeparate.
- C3: disabled sound, reduced motion и отказ в разрешении напоминаний имеют честное поведение.
- C4: напоминания реально проверяются после закрытия и перезагрузки, а VPN — на каждом устройстве.

## Task C1: Клиентский обмен и схождение двух копий

**Files:** Create `app/lib/sync/{sync_transport,sync_engine}.dart`, `app/test/sync/{sync_engine,two_clients}_test.dart`, `app/integration_test/two_clients.dart`. Modify `app/lib/app.dart`, `tools/verify.ps1`, `docs/verification.md`.

**Interfaces:**
- Consumes protocol.dart B1 и TaskRepository B2.
- Produces `SyncTransport.exchange(SyncRequest):Future<SyncResponse>`, `HttpSyncTransport(Uri endpoint, Future<String> Function() tokenProvider,{required bool allowDebugLoopback})`.
- `SyncEngine(TaskRepository repository,SyncTransport transport,{required String deviceId,required Scheduler scheduler})`, `syncNow():Future<void>`, `setForeground(bool):void`, `dispose():void`; `state` содержит localSaved/syncing/synced/offline/authRequired/rejected и lastSuccessAt.
- Scheduler порт: `schedule(Duration,void Function()):CancelHandle`, `now():DateTime`, `jitter():double` в 0…1. Тестовая реализация управляет временем без реальных задержек.
- Для зависимостей pendingBatch исключает операции до подтверждения dependsOn. Размер проверяется по UTF-8 всего JSON request перед отправкой; при переполнении последний элемент переносится в следующий batch. Таймаут сети 10 секунд.

- [ ] **Step 1: Записать сценарии с двумя отдельными файловыми БД и настоящим сервером A4.**

```dart
await clientA.execute(createBread);
await engineA.syncNow();
await engineB.syncNow();
expect((await clientB.readTask(breadId))!.title, 'Хлеб');
// Сервер принял complete, transport потерял ответ.
await engineA.syncNow();
await engineA.syncNow();
await engineB.syncNow();
expect(await countSuccessors(clientB, ruleId), 1);
```

Сервер запускается через Process с временным каталогом и тестовым ключом, порт свободный loopback; cleanup завершает только запущенный процесс. countSuccessors читает проекцию B2. Добавить два complete в разные дни, правку предварительного потомка до ack, delete+late edit, перезапуск после ответа до локального commit, страницу из 501 изменений, Unicode batch >256 КиБ и постоянную rejected операцию рядом с независимой. Проверить, что одновременно выполняется не больше одного exchange; foreground=false отменяет polling, foreground=true запускает сразу; 401 не повторяется каждую секунду.

- [ ] **Step 2: `flutter test test/sync` падает до реализации.**
- [ ] **Step 3: Реализовать transport и engine с обычной TLS проверкой и атомарным applySyncResponse.** Не менять badCertificateCallback. HTTP allowDebugLoopback работает только в debug и для 127.0.0.1, localhost или ::1. Состояния и retry не очищают очередь. На ACK завершения сопоставить provisional id каноническому и перенаправить ожидающие команды, сохранив их поля.
- [ ] **Step 4: Полный `flutter test`, server `npm test` и интеграционный сценарий двух клиентов проходят.** В verification.md записать именно два клиента на одной машине; это не доказательство обмена с телефоном через интернет.
- [ ] **Step 5: Коммит `feat: synchronize independent task clients reliably`.**

## Task C2: Подключение и защищённый ключ

**Files:** Create `app/lib/sync/connection_service.dart`, `app/lib/platform/secure_connection_store.dart`, `app/lib/features/settings/connection_panel.dart`, `app/test/sync/connection_service_test.dart`, `app/test/features/connection_panel_test.dart`. Modify `app/lib/{main,app}.dart`, `app/pubspec.yaml`, `docs/development.md`.

**Interfaces:**
- Consumes transport C1, backup B4 и AppDatabase B2.
- Produces `SecureConnectionStore.read(String profileId):Future<ConnectionSecret?>`, `write(String profileId,ConnectionSecret):Future<void>`, `delete(String profileId):Future<void>` через flutter_secure_storage.
- `ConnectionService.inspect(Uri endpoint,String token):Future<RemoteWorkspacePreview>` выполняет только пустой обмен cursor=0, не отправляет локальные задачи.
- `connect(RemoteWorkspacePreview,ConnectionChoice choice):Future<ConnectionResult>`, choice=merge|openSeparate; `disconnect():Future<void>` прекращает сеть и не удаляет БД.
- RemoteWorkspacePreview содержит workspaceId, endpoint, remoteCount, localCount, pendingCount и одноразовый handle к ключу в памяти. При merge совпадающие id явно перечисляются количеством и текстом «Локальные поля заменят совпадающие данные»; отдельный выбор openSeparate сохраняет старую БД вместе с pending.

- [ ] **Step 1: Записать тесты потери связи и смены набора.**

```dart
final preview = await connections.inspect(remoteUri, testKey);
expect(fakeTransport.lastRequest.operations, isEmpty);
expect(currentRepositoryPendingCount, greaterThan(0));
await connections.connect(preview, ConnectionChoice.openSeparate);
expect(await oldWorkspaceHasPendingOperations(), isTrue);
expect(await backupExistsForOldWorkspace(), isTrue);
```

Добавить отмену после preview, invalid key, другой workspace, сбой secure storage и отсутствие изменений старой конфигурации при неуспешном подключении. При merge title и note по совпадающему id получают выбранные локальные значения, новые remote записи сохраняются.

- [ ] **Step 2: `flutter test test/sync/connection_service_test.dart test/features/connection_panel_test.dart` падает.**
- [ ] **Step 3: Реализовать preview, safety backup и переключение отдельных файлов workspace.** Записать защищённый ключ только после успешной проверки и выбранного действия. Поле ключа скрыто, не попадает в debug output. UI показывает понятную ошибку сертификата или ключа; не предлагает отключить TLS.
- [ ] **Step 4: Повторить тесты; вручную подключить два Windows экземпляра с отдельными data directories к тестовому сервису, создать задачи в обе стороны.** Проверить перезапуск и восстановление подключения без повторного ввода ключа.
- [ ] **Step 5: Коммит `feat: connect personal workspace without losing local data`.**

## Task C3: Движение, звук и напоминания

**Files:** Modify `app/lib/platform/feedback_service.dart`, `app/lib/theme/motion_tokens.dart`, `app/lib/features/tasks/task_row.dart`, `task_home.dart`, `task_detail_panel.dart`, `app/lib/{main,app}.dart`, `app/pubspec.yaml`, `app/android/app/src/main/AndroidManifest.xml`, Android MainActivity и Windows runner platform channel. Create `app/lib/platform/reminder_service.dart`, `app/assets/sounds/{complete,undo}.wav`, `app/test/platform/{feedback,reminder}_test.dart`, `app/test/features/task_motion_test.dart`, `docs/platform-notifications.md`.

**Interfaces:**
- Consumes CompletionFeedback B3, localSettings B4 и реальные TaskItem состояния B2/C1.
- Produces `LocalCompletionFeedback` implementing CompletionFeedback; `SoundPolicy.mayPlay():Future<bool>` считывает локальное разрешение приложения и системный режим.
- `ReminderService.reconcile(List<TaskItem>):Future<ReminderReport>`, `requestPermission():Future<ReminderPermission>`, `onNotificationTaskId:Stream<String>`. ReminderPermission=granted|denied|needsExactAlarmPermission|unsupportedPackage. ReminderReport перечисляет scheduled/cancelled/failures по taskId.
- Устойчивая таблица notificationIds отображает UUID задачи в уникальный положительный int32, без коллизии простого hashCode. Удаление всех задач не переиспользует id до отмены старых расписаний.

- [ ] **Step 1: Записать meaningful тесты отклика и расписаний.**

```dart
await feedback.onUserCompletion(undo:false);
expect(audio.playCount, 1);
settings.completionSoundEnabled = false;
await feedback.onUserCompletion(undo:false);
expect(audio.playCount, 1);
await reminders.reconcile([taskAtTen]);
await reminders.reconcile([taskAtEleven]);
expect(notifications.cancelledIds, contains(taskNotificationId));
expect(notifications.latestSchedule.time, elevenUtc);
```

Добавить SoundPolicy=false → ноль проигрываний; remote completion → ноль вызовов CompletionFeedback; reduced motion → нет продолжающегося контроллера после pump; повторный reconcile одинакового списка не дублирует расписание; denied не возвращает scheduled; удалённая задача отменяет; два UUID получают разные int32; нажатие уведомления открывает taskId.

- [ ] **Step 2: Запустить `flutter test test/platform test/features/task_motion_test.dart`; получить FAIL до реализации.**
- [ ] **Step 3: Реализовать Duration 140/180/220/240 мс для check/strike/reflow/panel и disableAnimations.** Во время перестройки использовать стабильные task keys и прерываемые переходы. Создать собственные тихие WAV complete=110 мс, undo=90 мс с плавной огибающей, без чужих звуковых файлов. Запускать звук после успешного локального commit без задержки сохранения. Android SoundPolicy проверяет AudioManager ringer mode, Windows — доступное системное состояние уведомлений через SHQueryUserNotificationState; при системном запрете отклик остаётся визуальным. Настройки громкости системы не меняются. Дополнительно проверить поведение реального focus/беззвучного режима, поскольку аудио плагин сам по себе это не доказывает.

  Пределы API: [SHQueryUserNotificationState](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shqueryusernotificationstate) сообщает состояния присутствия и презентации; QUNS_QUIET_TIME не равен современному режиму Focus Assist. Не считать QUNS_ACCEPTS_NOTIFICATIONS достаточным доказательством отсутствия Do Not Disturb. До обозначения системного поведения готовым провести реальную проверку C4 и скорректировать платформенный адаптер при расхождении. Android режим проверяется по [AudioManager.getRingerMode](https://developer.android.com/reference/android/media/AudioManager#getRingerMode()).
- [ ] **Step 4: Подключить локальные одноразовые уведомления через timezone и flutter_local_notifications.** Настроить Android разрешения/receivers и восстановление после reboot. Обычный runtime запуск не запрашивает разрешение: только установка первого напоминания. Отменять старое расписание до нового. Для Windows без identity показывать unsupportedPackage, а не обещать полноценное управление уведомлениями. В timezone тестах включить Europe/Moscow и DST зону America/New_York; UTC момент существующего напоминания при смене зоны устройства сохраняется.
- [ ] **Step 5: Повторить тесты и Windows smoke; коммит `feat: add gentle feedback and native reminders`.** Проверки закрытого приложения и перезагрузки выполняются для установленных сборок в C4, не заявляются пройденными здесь.

## Task C4: Сборки и проверка двух устройств

**Files:** Create `tools/package-release.ps1`, `docs/{installation,verification}.md`; modify `tools/verify.ps1`, `app/pubspec.yaml` для msix_config, Windows/Android package metadata и root `.gitignore`.

**Interfaces:**
- Consumes готовое приложение C1–C3 и сервис A4.
- Produces `releases/<version>/day-windows.zip`, `day-windows.msix`, `day-android.apk`, `SHA256SUMS.txt`, отдельный verification.md со статусом каждого испытания.
- `tools/verify.ps1` выполняет server tests, flutter analyze, flutter test и возвращает ненулевой exit при любой ошибке. `tools/package-release.ps1 -Version <semver>` запускает release сборки и хеширует только полученные артефакты.

- [ ] **Step 1: Добавить integration_test/smoke.dart: создать задачу, закрыть repository, заново открыть и найти её; открыть детали и установить срок; переключить тему.** Сценарий использует временный test data directory. До финальной интеграции он должен обнаруживать отсутствующий wire-up, а не только проверять тестовый fake.
- [ ] **Step 2: Выполнить полные автоматические проверки и smoke на Windows.** Просмотреть 360/412 и 760/1024/1440, длинную кириллицу, 1000 задач и масштаб текста. Артефакты формируются только после PASS. Flutter debug кадры не выдаются за release performance измерение.
- [ ] **Step 3: Собрать `flutter build windows --release`, `flutter build apk --release` и MSIX через выбранную совместимую версию msix.** Для личного Android APK использовать отдельный локальный keystore в игнорируемом каталоге, пароль не хранить в коде; для MSIX использовать отдельный локальный сертификат. Установку доверия сертификату пользователь выполняет явным действием, без скрытой модификации хранилища доверия. Windows ZIP содержит все DLL и data, а не один EXE. Сертификат не публикуется с закрытым ключом.
- [ ] **Step 4: Заполнить реальную матрицу испытаний.** Windows MSIX: уведомление в foreground, после закрытия, после изменения и удаления. Android телефон: установка, разрешения, клавиатура, беззвучный режим, перезагрузка и уведомления. Для локального USB теста допустим adb reverse и debug loopback; такой тест явно помечается USB, не интернет синхронизация. Затем предоставить пользователю конкретную сборку и параметры размещения сервиса, получить доступ к нужному серверу только когда он понадобится. После HTTPS размещения проверить Windows ↔ Android с VPN on/off, офлайн и восстановлением сети. Для каждой строки записать PASS, FAIL или NOT VERIFIED и причину; файлы задач и ключей в отчёт не включать.
- [ ] **Step 5: Исправить реальные сбои, повторить только затронутые проверки и сделать коммит `release: package personal planner and record device checks`.** Дать пользователю ссылки на файлы, краткую установку и фактические ограничения. Если сервер или телефон пока недоступен, передать сборки и точный оставшийся шаг, не объявляя полную готовность синхронизации.

## Результат этапа

Реализация считается завершённой по общему критерию только при проверках устройств и доступности сервиса. Возможность собрать APK на компьютере не равна проверке Android поведения; локальный сервер не равен доступному из интернета серверу.
