---
name: release
description: Готовит и выпускает новую версию «Метро-таймер: Київ» в App Store — номер сборки, генерация проекта, тесты, тексты витрины, архив, экспорт, проверка .ipa, загрузка, страница версии, журнал READINESS. Использовать, когда пользователь говорит «готовим обновление», «релиз», «заливаем версию», «собери архив», «отправляй в App Store».
---

# Релиз «Метро-таймера»

Порядок выведен из релизов 1.0–1.3. Каждый шаг заканчивается проверкой; следующий не
начинать, пока проверка не прошла. Перед началом: прочитать последний раздел
`docs/READINESS.md` (уроки отказов App Review) и прогнать скилл `city-data` — релиз с
устаревшим графиком хуже, чем релиз на день позже.

## Границы

- Пароли Apple ID, коды 2FA и ключи не вводить и не просить. Вход в Xcode и App Store
  Connect — руками пользователя.
- «Отправить на проверку» и публикация поста — только после явного слова пользователя в чате.
- Пуш — только по слову «пушь».
- Репозиторий публичный: `.p8`, `.p12`, профили, Key ID и Issuer ID в файлы не писать.

## 1. Версия и сборка

1. Версия витрины — `MARKETING_VERSION` в `Scripts/gen_pbxproj.py`.
2. Номер сборки всегда растёт и не переиспользуется даже между версиями
   (1.3 ушла со сборкой 8). Текущий:
   `grep -m1 CURRENT_PROJECT_VERSION MetroTimer.xcodeproj/project.pbxproj`
3. `MT_BUILD=<текущий+1> python3 Scripts/gen_pbxproj.py`

Проверка: `git diff --stat` показывает только `project.pbxproj` и скрипт; в pbxproj новые
`MARKETING_VERSION` и `CURRENT_PROJECT_VERSION` в обоих таргетах.

## 2. Тесты

```bash
xcodebuild -project MetroTimer.xcodeproj -scheme MetroTimer \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' test
```

Имя симулятора — из `xcrun simctl list devices available`. Все зелёные. Если число тестов
изменилось — обновить его в `README.md` («N tests») и в `docs/FEEDBACK.md`.

## 3. Прогон в симуляторе

Полная матрица — `docs/TESTPLAN.md`, строки **S**; итог записать в её журнал.
Debug-аргументы — `docs/BUILD.md`, «Debug hooks». Минимум: маршрут с пересадкой, маршрут
через мост при `-MTForceAlert 1`, поездка после 23:00, английский язык
(`-AppleLanguages "(en)"`). Старую установку удалить, иначе восстановленная поездка
испортит картину.

Чего симулятор не покажет — и что честно записать в READINESS как «не проверено на
устройстве»: вид острова и экрана блокировки на железе, жесты двумя пальцами, доставку
time-sensitive уведомлений сквозь Фокус.

## 4. Тексты витрины

- «Що нового» — `AppStore/metadata_uk.md` и `AppStore/metadata_en.md`, оба языка.
- Лимиты: название 30, подзаголовок 30, промо-текст 170, ключевые слова 100, «Що нового» 4000.
  Кириллицу считать через `python3 -c "print(len(open(...).read()))"`, не `wc -m`.
- Скриншоты: ни слова о цене («безкоштовно», «free», скидки) — отказ 2.3.7 от 24.08.2026.
- Изменилась работа с данными или сетью — политика конфиденциальности правится в трёх
  местах сразу (см. `CLAUDE.md`).

## 5. Архив и экспорт

```bash
xcodebuild archive -project MetroTimer.xcodeproj -scheme MetroTimer \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build-archive/MetroTimer.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build-archive/MetroTimer.xcarchive \
  -exportOptionsPlist AppStore/ExportOptions.plist \
  -exportPath build-archive/export -allowProvisioningUpdates
```

`build-archive/` не в гите.

## 6. Проверка .ipa — смотреть, а не предполагать

```bash
rm -rf build-archive/ipa-check && unzip -q build-archive/export/MetroTimer.ipa -d build-archive/ipa-check
APP=build-archive/ipa-check/Payload/MetroTimer.app
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" -c "Print CFBundleVersion" $APP/Info.plist
codesign -dvv $APP 2>&1 | grep Authority | head -1
codesign -d --entitlements - $APP 2>/dev/null | grep -A2 "get-task-allow\|time-sensitive"
ls $APP/PlugIns/MetroTimerWidget.appex/PrivacyInfo.xcprivacy $APP/PrivacyInfo.xcprivacy $APP/kyiv_metro.json
```

Ожидаемо: версия и сборка из шага 1; «Apple Distribution: Vladyslav Domotskyi (JC2G64UQ8N)»;
`get-task-allow = false`; `time-sensitive = true`; виджет вложен; манифесты приватности в
обоих таргетах; JSON на месте.

## 7. Загрузка

- Есть `~/.appstoreconnect/private_keys/AuthKey_*.p8` → `xcrun altool --validate-app`, затем
  `--upload-app` (Key ID и Issuer ID пользователь даёт в чате на один раз; в файлы не писать).
- Ключа нет (так на нынешнем Mac) → скопировать архив в
  `~/Library/Developer/Xcode/Archives/<гггг-мм-дд>/MetroTimer <версия> (<сборка>).xcarchive`,
  открыть Organizer, пользователь сам жмёт Distribute App → App Store Connect → Upload.

Сборка появляется в App Store Connect через 5–20 минут после загрузки.

## 8. Страница версии

Новая версия → «Що нового» на обоих языках → промо-текст → выбрать сборку → сохранить.
Дальше — слово пользователя. После отправки не трогать метаданные до ответа App Review.

## 9. После выхода

1. Факт релиза проверить снаружи:
   `curl -s "https://itunes.apple.com/lookup?id=6804173309&country=ua" | python3 -c "import sys,json; r=json.load(sys.stdin)['results'][0]; print(r['version'], r['currentVersionReleaseDate'])"`
2. `docs/READINESS.md` — раздел версии: дата, сборка, что проверено и что **не** проверено.
3. `docs/FEEDBACK.md` — статусы ✅ в таблице приоритетов.
4. `README.md` — строка Status, число тестов.
5. Сайт, если лендинг упоминает новое: `AppStore/site/` → копия в `../METRO` → пуш оттуда.
6. Коммиты по-украински («Область: що змінилося»), тег `v<версия>`.
7. Пост — скилл `threads-post`.
8. Напомнить пользователю: обновиться самому и проехать одну поездку, ответить на свежие
   отзывы в App Store Connect.
