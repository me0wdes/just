# Just

**Скачать:** [последняя версия](https://github.com/me0wdes/just/releases/latest) для Windows, macOS и Android.

Личный повседневный планировщик для Windows и Android. Проект сохранён в `C:\AI FOLDER\Claude work\Just`. Android-сборка отложена пользователем, лицензия SDK не принята.

GitHub: [me0wdes/claude-work → Just](https://github.com/me0wdes/claude-work/tree/main/Just). Локальная история Just хранится в собственном Git; на GitHub проект публикуется как обычная подпапка общего репозитория. При обновлении сохранять остальные папки `claude-work`. Локальные инструменты, данные, ключи подписи и готовые сборки исключены из Git.

Работают локальные задачи, Сегодня/Все/свои списки, поиск по названиям и заметкам, сроки, выбранные дни повтора, две темы, короткий отклик и JSON копии. Сервис синхронизации и обмен двух независимых клиентских баз проверены локально. Для настоящего обмена с телефоном ещё нужен доступный HTTPS сервер и Android-сборка.

## Запуск

Готовая Windows-версия 0.2.0: [скачать ZIP](https://github.com/me0wdes/claude-work/raw/refs/heads/main/Artifacts/Just/0.2.0/Just-0.2.0-Windows.zip). Репозиторий приватный, поэтому для скачивания нужен вход в GitHub. Распаковать архив целиком и открыть day_planner.exe. Локальные сборки находятся в `releases/0.2.0`; для системных напоминаний предусмотрен MSIX, установка доверия личному сертификату выполняется только пользователем.

[Свой сервер синхронизации](docs/self-hosting.md) · [Установка и подключение](docs/installation.md) · [review и исправления](docs/review-2026-10-19.md) · [фактическая проверка](docs/verification.md) · [сервис](server/README.md) · [разработка](docs/development.md).

## Дизайн

Версия 0.2 перенесена из [макета в Figma](https://www.figma.com/design/EZlfyymBK6A37m0OYSLjb9/Just): цвета и размеры совпадают с переменными «Just · цвета» и «Just · размеры», компоненты повторяют карточку дела, фильтры, поле добавления, сайдбар и «Шапку экрана». Элементы нейтральные, галочки выполненных дел зелёные. В шапке живое поле FLOW по времени суток: 04–12 Rose gold, 12–19 Solar flare, 19–04 Night (рецепты в `docs/references`). Звук на каждое действие: 11 тонов из `tools/generate_sounds.py`. Скриншоты в `docs/screenshots`.


Иконки ItsHover, короткие пружинные отклики по Fluid Functionalism и приветствие с живым FLOW фоном Rose gold из предоставленного экспорта. [Рецепт, источники и адаптация для следующих агентов](docs/references/ui-motion-and-rose-gold.md).

Основа — личная [библиотека референсов](../Design%20Reference%20Library/START_HERE.md), [четыре выбранных ориентира](docs/references/README.md) и [исследование интерфейсов в Lazyweb](https://www.lazyweb.com/agentic-search/05af5799-5051-4a05-9a67-ebc314669f46). Материалы личной библиотеки не загружались во внешние сервисы.

[Спецификация](docs/superpowers/specs/2026-10-18-everyday-todo-design.md) и [план](docs/superpowers/plans/2026-10-19-everyday-todo-plan.md) согласованы пользователем. Работа выполняется в ветке feat/day-planner. Внешнего размещения, публикации и изменения доверенных сертификатов не было.
