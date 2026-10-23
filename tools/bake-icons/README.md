# bake-icons

Переносит анимации [ItsHover](https://github.com/itshover/itshover) в `app/lib/theme/icon_motion.g.dart`.
Каждая иконка запускается в Chromium, её `startAnimation` и `stopAnimation` снимаются по кадрам,
а Flutter проигрывает эти кадры в `DayIcon`.

```bash
git clone --depth 1 https://github.com/itshover/itshover /tmp/itshover && cp -r /tmp/itshover/icons .
npm install && npx playwright-core install chromium
npm run bake
```

Какая иконка ItsHover стоит за каким ключом приложения, задаёт `map.json`.

Иконка приложения: экспортируйте фрейм «Icon» из Figma (node 78:2742) в 1024 px
в `app/assets/brand/icon.png` и запустите `node app-icon.mjs`. Скрипт нарежет её для Windows (.ico), macOS и Android.
