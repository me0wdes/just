# Разработка

Flutter 3.47.7 stable, Dart 3.13.5, Windows x64. Официальный архив проверен SHA256 `c2c875da25a1a1448d18ee4e8f398b2f6fce888b4775d8f9130538e16d826cb4` и распакован в `.tools/flutter`. Инструменты и кэши игнорируются Git. `tools/setup-dev.ps1` повторяет загрузку stable на новом компьютере; версия текущего проекта зафиксирована здесь и в lockfile пакетов.

Из app/: `../tools/flutter.ps1 test`, `../tools/flutter.ps1 analyze`, `../tools/flutter.ps1 build windows`. Обёртка задаёт только переменные текущего процесса: локальные PUB_CACHE, APPDATA для аналитики/настроек инструментов, GRADLE_USER_HOME. Глобальный PATH не меняется.

19 октября: doctor подтверждает Flutter и MSVC 14.44.35207, но отсутствуют Windows CMake/SDK и Android SDK/JDK. Установочные сборки до подготовки этих компонентов не проверены. Кэш и конфигурация пользовательских задач отделены от кэша разработки.

Windows CMake, Windows SDK 10.0.26100 и ATL установлены с разрешения пользователя. Flutter Native Windows smoke и release build проходят. Android command tools/JDK подготовлены локально, но SDK license отклонена по решению пользователя, platform/build-tools/NDK не установлены. Никакой глобальный PATH не менялся.
