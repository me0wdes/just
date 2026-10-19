# Sync Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Получить отдельно запускаемый личный сервис синхронизации с постоянной SQLite БД и воспроизводимой защитой от дублей и потерь.

**Architecture:** Node.js HTTP обработчик проверяет ключ и ограничивает тело запроса. Синхронная транзакция SQLite применяет подтверждённые операции и формирует постраничный журнал изменений; содержимое задач не пишется в журналы процесса.

**Tech Stack:** Node.js 24, node:http, node:crypto, node:sqlite, node:test, uuid для UUIDv5.

**Spec:** [Спецификация](../specs/2026-10-18-everyday-todo-design.md), [общий план и JSON контракты](2026-10-19-everyday-todo-plan.md).

## Global Constraints

- Применяются все Global Constraints общего плана, включая 100 операций, 256 КиБ, один workspace и обычную проверку TLS.
- Длина названия 1…500 Unicode code points, заметки 0…10000; даты YYYY-MM-DD проверяются как реальные календарные даты.
- UUIDv5 следующего повтора одинаков для Dart и Node. Локальные часы не определяют очередность конфликтов.
- Удаления и подтверждения operationId не очищаются по времени в первой версии.
- Тесты используют временные файлы и тестовые ключи; реальные пользовательские задачи не нужны.

## Review Focus

- A1: одинаковое поведение на кириллице, emoji и крайних длинах.
- A2: WAL backup и перезапуск после commit не теряют подтверждения.
- A3: два завершения в разные дни порождают одну следующую задачу.
- A3: удаление списка и запоздалые правки сохраняют задачи во Входящих.
- A4: граница размера считается по байтам, ключ и текст задач отсутствуют в ошибках и логах.

## Task A1: Контракт и проверка входных данных

**Files:** Create `contracts/sync-v1.md`, `contracts/fixtures/{valid-sync,unicode,invalid-sync,recurrence}.json`, `server/package.json`, `server/src/validation.mjs`, `server/test/validation.test.mjs`.

**Interfaces:**
- Produces `normalizeTitle(value:unknown):string`, `validateNote(value:unknown):string`, `validateLocalDate(value:unknown):string`, `validateRequest(value:unknown):SyncRequest`.
- Ошибка валидации имеет `code:string`, `field:string`; не содержит полный запрос или токен.
- Fixtures используют формат общего плана и зарезервированный Inbox id. Даты повторов содержат входное правило, dueDate, completionDate и ожидаемую nextDate.

- [ ] **Step 1: Записать негативные и граничные тесты.**

```js
assert.equal(normalizeTitle('  Купить молоко 🥛  '), 'Купить молоко 🥛');
assert.equal([...normalizeTitle('😀'.repeat(500))].length, 500);
assert.throws(() => normalizeTitle('😀'.repeat(501)), {code:'title_too_long'});
assert.throws(() => normalizeTitle(' \n '), {code:'title_empty'});
assert.throws(() => validateLocalDate('2026-02-30'), {code:'invalid_date'});
assert.throws(() => validateRequest({...validRequest, operations:Array(101).fill(validOperation)}), {code:'too_many_operations'});
```

`validRequest` и `validOperation` берутся из valid-sync.json. Дополнительно отклонить неизвестные поля, неизвестный kind, отрицательный cursor, weekly дни 0 и 8 и monthly день 32.

- [ ] **Step 2: Запустить `node --test server/test/validation.test.mjs`; получить FAIL из-за отсутствующих экспортов.**
- [ ] **Step 3: Реализовать перечисленные функции, schema fixtures и package.json с `type:module`, `engines.node:>=24` и тестовой командой.** Зависимость uuid подключается здесь для следующей задачи; её версия фиксируется package-lock.json после установки. Проверка длины использует code points, а не UTF-16 length.
- [ ] **Step 4: Повторить команду; все случаи проходят, все fixtures валидируются или ожидаемо отклоняются.**
- [ ] **Step 5: Сохранить коммит `feat: define sync protocol and validation`.**

## Task A2: Постоянная БД и корректная резервная копия

**Files:** Create `server/src/{store,backup}.mjs`, `server/test/{store,backup}.test.mjs`, `server/test/helpers.mjs`.

**Interfaces:**
- Consumes валидированные сущности и EntityChange из A1.
- Produces `openStore(filename:string, {workspaceId:string, clock:()=>string}):SyncStore`.
- SyncStore: `transaction<T>(fn:()=>T):T`, `getEntity(type,id):object|null`, `putEntity(type,id,value):number`, `getAcknowledgement(operationId):Ack|null`, `putAcknowledgement(ack):void`, `changesAfter(cursor:number,limit:number):{changes,nextCursor,hasMore}`, `backupTo(path:string):Promise<void>`, `close():void`.
- Тестовый `temporaryStore()` создаёт изолированный каталог и возвращает `{store,filename,cleanup}`. База содержит meta, entities, changes и acknowledgements; индексы по revision и operationId.

- [ ] **Step 1: Записать тесты транзакции, открытия после закрытия и WAL backup.**

```js
assert.throws(() => store.transaction(() => {
  store.putEntity('task', task.id, task);
  throw Error('interrupted');
}));
assert.equal(store.getEntity('task', task.id), null);
// После успешной транзакции закрыть и заново открыть тот же файл.
assert.equal(reopened.getAcknowledgement(opId).status, 'applied');
assert.equal(reopened.getEntity('task', task.id).title, task.title);
await store.backupTo(backupPath);
assert.equal(backupStore.getEntity('task', task.id).title, task.title);
```

Добавить 501 событие: первая страница 500, hasMore=true и nextCursor=500; вторая выдаёт оставшееся. Tombstone присутствует в change выдаче.

- [ ] **Step 2: Запустить `node --test server/test/store.test.mjs server/test/backup.test.mjs`; подтвердить FAIL до реализации.**
- [ ] **Step 3: Реализовать SyncStore на DatabaseSync, WAL и транзакциях BEGIN IMMEDIATE/COMMIT/ROLLBACK.** В transaction нет await. `backupTo` использует штатный backup API node:sqlite, а не копирование одного файла активной БД. Секреты не хранятся в этих таблицах.
- [ ] **Step 4: Повторить команду; проверить откат, persistence, paging и восстановление backup.**
- [ ] **Step 5: Коммит `feat: persist sync state and verified backups`.**

## Task A3: Обмен, конфликты и повторяющиеся задачи

**Files:** Create `server/src/{sync,recurrence}.mjs`, `server/test/{sync,recurrence}.test.mjs`.

**Interfaces:**
- Consumes SyncStore из A2, validateRequest из A1.
- Produces `applySync(store:SyncStore, request:SyncRequest):SyncResponse`, `nextOccurrence(rule:Rule,dueDate:string|null,completionDate:string):string`, `successorId(ruleId:string,occurrenceDate:string):string`.
- `applySync` проверяет зависимости, сохраняет Ack и изменения в одной транзакции. Обычный patch изменяет только разрешённые changes. Complete/undoComplete и delete/restore — отдельные переходы.
- Undo payload содержит `completionId`. Если потомок редактировался после создания, вернуть Ack rejected с `code:successor_modified` и не менять исходное завершение.

- [ ] **Step 1: Записать сценарные тесты с двумя deviceId.**

```js
const first = applySync(store, requestA);
const retry = applySync(store, requestA);
assert.equal(retry.acknowledgements[0].status, 'duplicate');
assert.deepEqual(retry.acknowledgements[0].effect, first.acknowledgements[0].effect);
assert.equal(allSuccessorsOf(ruleId).length, 1);
assert.equal(nextOccurrence(monthly31, '2026-01-31', '2026-01-31'), '2026-02-28');
assert.equal(nextOccurrence(monthly31, '2028-01-31', '2028-01-31'), '2028-02-29');
```

`allSuccessorsOf` — вспомогательный запрос тестового store из helpers.mjs. Добавить: A меняет title, B note → оба сохранены; A/B меняют title → последнее принятое; delete → поздний patch не восстанавливает; deleteList → задачи и поздние новые привязки во Входящих; complete в разные дни → эффект первого завершения; undo изменённого потомка → successor_modified; restore snapshot завершённой истории не генерирует потомка и не принимает присланную revision; rejected независимой операции не блокирует остальные. Fixtures покрывают weekly переход года и monthly 29–31.

- [ ] **Step 2: Запустить `node --test server/test/sync.test.mjs server/test/recurrence.test.mjs`; зафиксировать ожидаемый FAIL.**
- [ ] **Step 3: Реализовать функции и переходы.** Для каждой применённой операции сохранить canonical effect. Детерминированные id строятся через uuid.v5 с namespace ruleId. Повтор duplicate не меняет ревизию. История прошлых событий не заменяется текущей максимальной ревизией при paging.
- [ ] **Step 4: Повторить тесты и полный `npm --prefix server test`; все сценарии проходят.**
- [ ] **Step 5: Коммит `feat: merge personal task changes without duplicates`.**

## Task A4: HTTP сервис, ключ подключения и запуск

**Files:** Create `server/src/{http,index}.mjs`, `server/test/http.test.mjs`, `server/README.md`, `server/.env.example`, `tools/verify.ps1`.

**Interfaces:**
- Consumes applySync, openStore и validateRequest.
- Produces `createHttpServer({store,tokenHash:Buffer,logger}):http.Server`; CLI `node server/src/index.mjs --data <directory> --port <number>`.
- Ключ задаётся переменной `DAY_SYNC_TOKEN`, минимум 32 случайных байта в base64url. Отдельная CLI команда `--generate-token` выводит новый ключ только при явном вызове, обычный запуск его не печатает. Сравнение SHA256 ключа выполняется timingSafeEqual.
- По умолчанию bind 127.0.0.1. Локальный процесс доступен HTTPS прокси по тому же компьютеру; наружу напрямую HTTP не публикуется.

- [ ] **Step 1: Добавить HTTP тесты на случайном свободном loopback порту.**

```js
assert.equal((await syncFetch({token:'wrong'})).status, 401);
assert.equal((await syncFetch({rawBody:Buffer.alloc(262145)})).status, 413);
assert.equal((await syncFetch({body:validRequest})).status, 200);
assert.equal(logLines.join('').includes(testToken), false);
assert.equal(logLines.join('').includes('Личная задача'), false);
```

Проверить UTF-8 многобайтный запрос >256 КиБ, обрыв тела, ошибку JSON, неизвестный маршрут и возврат workspaceId на пустой синхронизации cursor=0. В ошибке не должно быть stack trace или исходного body.

- [ ] **Step 2: Запустить `node --test server/test/http.test.mjs`; подтвердить FAIL.**
- [ ] **Step 3: Реализовать HTTP слой и CLI.** Ограничить поток до JSON parse, возвращать структурированные ошибки. Документировать Node версию, TLS прокси, переменные, backup/restore и вызов клиента с пустыми данными. verify.ps1 выполняет имеющиеся server тесты; клиентские команды добавятся позже.
- [ ] **Step 4: Выполнить `npm --prefix server test`, поднять CLI с временной БД, сделать пустой обмен и повторить после перезапуска; данные сохранены.**
- [ ] **Step 5: Коммит `feat: expose authenticated personal sync service`.**

## Результат этапа

Сервис работает самостоятельно и проверен на тестовых данных. Он ещё не размещён в интернете и не доказывает доступность с VPN. Следующий этап — локальный клиент, затем реальное соединение.
