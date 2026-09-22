# Політика конфіденційності — «Метро-таймер: Київ»

*Оновлено: вересень 2026. Розробник: Владислав Домоцький, vladdomotsky@gmail.com.*

## Коротко

«Метро-таймер» не збирає і не передає жодних ваших даних. Усе, що застосунок
зберігає, залишається на вашому пристрої.

## Детально

**Мережа.** За замовчуванням застосунок працює повністю офлайн і не робить
жодних мережевих запитів. Єдиний виняток — перемикач «Показувати тривоги в
Києві» (вимкнений за замовчуванням): якщо ви його увімкнете, застосунок раз на
хвилину — і лише поки відкритий — запитує публічний фід статусів повітряних
тривог по областях.

Це звичайний запит без параметрів: ні ваших даних, ні ідентифікаторів, ні
маршрутів застосунок не надсилає. Як і при відкритті будь-якого сайту, серверу
фіду видно вашу IP-адресу і час запиту — ми цим не керуємо і нічого звідти не
отримуємо.

Джерело неофіційне: це публічний фід, а не офіційний канал оповіщення. Він може
відставати, помилятися або бути недоступним. Якщо перевірити не вдалося,
застосунок прямо показує «не вдалося перевірити» замість того, щоб мовчати
(мовчання читалося б як «тривоги немає»). Не покладайтеся на цей застосунок у
питаннях безпеки.

Реклами, аналітики, трекерів і сторонніх SDK немає.

**Геолокація.** Використовується лише коли застосунок відкритий (дозвіл
«Під час використання»):
- на головному екрані — один раз, коли він відкривається, щоб підказати найближчу
  станцію («Станція поруч»); координати обробляються на пристрої і не зберігаються;
- під час поїздки — тільки на наземних ділянках метро, щоб уточнити розрахункове
  положення поїзда; координати обробляються на пристрої і не зберігаються;
- у режимі калібрування, який ви вмикаєте вручну, усі отримані координати
  (у тому числі приблизні, під землею) записуються у файл на пристрої разом із
  часом — це трек вашої поїздки.

Нагадування «на станції», якщо ви його ввімкнете: зону станції відстежує сама iOS
і показує сповіщення, коли ви поруч. Застосунок вашого місця при цьому не бачить.

У фоні геолокація не використовується. Без дозволу на геолокацію застосунок
повністю функціональний.

**Дані руху (акселерометр).** Записуються лише в режимі калібрування. Записи
зберігаються у файлах застосунку на пристрої.

**Сповіщення і будильник.** Плануються локально на пристрої для попередження про
вихід. Будильник (iOS 26 і новіші) вмикаєте ви самі на екрані поїздки.

**Журнал поїздок і калібрування.** Зберігаються локально у сховищі застосунку
з файловим шифруванням і **навмисно виключені з резервних копій iCloud та
iTunes** — вони живуть тільки на цьому пристрої (тому при переїзді на новий
телефон не переносяться). Файли залишають пристрій лише якщо ви самі
експортуєте їх кнопкою «Експортувати»; перед експортом ви бачите список сесій
і розмір кожної (файл калібрування містить трек поїздки з часом). Видалити дані
можна кнопками на екрані «Про застосунок» або видаливши застосунок; відкликати
доступ до геолокації — у Параметрах iOS.

«Мій рік у метро» рахується з цього журналу на пристрої. Картинку з підсумком
ви надсилаєте самі, якщо захочете; сам застосунок нікуди її не відправляє.

**Діти.** Застосунок не збирає даних ні від кого, включно з дітьми.

## Зміни політики

У разі змін оновлена політика публікуватиметься за цією ж адресою і в застосунку.

## Контакт

Питання: vladdomotsky@gmail.com

---

# Privacy Policy — “Metro Timer: Kyiv” (English)

*Updated: September 2026. Developer: Vladyslav Domotskyi, vladdomotsky@gmail.com.*

Metro Timer does not collect or transmit any of your data. Everything the app
stores stays on your device.

- **Network.** By default the app is fully offline and makes no network requests.
  The only exception is the “Show air-raid alerts in Kyiv” switch (off by
  default): when enabled, the app queries a public feed of regional air-raid
  statuses once a minute, and only while the app is open. It is a plain request
  with no parameters — the app sends none of your data, identifiers or routes.
  As when you open any website, the feed’s server sees your IP address and the
  time of the request; we do not control that and receive nothing from it.
  The source is a public feed, not an official alert channel: it can lag, be
  wrong, or be unavailable. When a check fails the app says “could not check”
  outright rather than staying silent. Do not rely on this app for safety
  decisions. No ads, analytics, trackers or third-party SDKs.
- **Location.** Used only while the app is open (“While Using”). On the main
  screen — once, when it opens, to suggest the nearest station (“Station
  nearby”); coordinates are processed on device and not stored. During a trip —
  only on above-ground metro sections, to refine the train’s estimated position;
  coordinates are processed on device and not stored. In the manually enabled
  Calibration mode, all received coordinates (including approximate ones
  underground) are written to a file on the device together with timestamps —
  a track of your ride. For the station reminder, if you turn it on, iOS itself
  watches the station area and shows the notification when you are near; the
  app never sees your location. Location is never used in the background. The
  app is fully functional without location permission.
- **Motion data.** The accelerometer is recorded only in Calibration mode; the
  files stay on the device.
- **Notifications and alarm.** Scheduled locally on the device to warn you
  before your stop. The alarm (iOS 26 and later) is on only if you turn it on.
- **Trip journal and calibration.** Stored locally with file encryption and
  **deliberately excluded from iCloud and iTunes backups** — they live on this
  device only (so they do not carry over to a new phone). Files leave the device
  only if you export them yourself with the “Export” button; before exporting you
  see the list of sessions and the size of each (a calibration file contains a
  timestamped ride track). You can delete the data from the “About” screen or by
  deleting the app; location access can be revoked in iOS Settings. “My year on
  the metro” is calculated from this journal on the device; the summary image is
  sent only if you share it yourself.
- **Children.** The app collects no data from anyone, including children.

Contact: vladdomotsky@gmail.com
