# App Store — метадані (українська)

## Назва (до 30 символів)
Метро-таймер: Київ

## Підзаголовок (до 30 символів)
Не проспи свою станцію

## Промо-текст (до 170 символів)
Таймер поїздки в київському метро прямо в Dynamic Island. Працює без інтернету — навіть у тунелі. Попередить за одну станцію до виходу.

## Опис

Їдеш у метро — читаєш, дрімаєш, слухаєш музику? «Метро-таймер» простежить за маршрутом замість тебе.

Обери станцію відправлення і станцію призначення, натисни «Поїхали» — і на екрані блокування та в Dynamic Island з'явиться зворотний відлік до твоєї станції з кількістю зупинок, що залишилися. За одну станцію до виходу телефон завібрує: «Наступна — твоя. Готуйся до виходу».

ПРАЦЮЄ ОФЛАЙН
Під землею немає зв'язку — і він не потрібен. Застосунок розраховує положення поїзда за офіційним графіком метрополітену. Жодних серверів, жодної реклами, жодної аналітики. Інтернет потрібен рівно одній функції — показу повітряних тривог, і вона вимкнена за замовчуванням: вмикаєте ви самі.

DYNAMIC ISLAND І ЕКРАН БЛОКУВАННЯ
Відлік часу та лічильник зупинок живуть у Dynamic Island (iPhone 14 Pro і новіші) та на екрані блокування (будь-який iPhone з iOS 16.1+). Застосунок можна закрити — таймер і сповіщення працюватимуть далі.

ПЕРЕСАДКИ
Маршрути між лініями будуються автоматично через пересадочні вузли. Окреме сповіщення підкаже, де перейти на іншу лінію.

РОЗУМНЕ УТОЧНЕННЯ
На наземних ділянках (лівий берег червоної лінії, південь зеленої) застосунок сам звіряє розрахунок із GPS і виправляє відхилення. Схибив розрахунок під землею — кнопки −1/+1 зсунуть маршрут на одну зупинку, просто з Dynamic Island.

ТВОЇ ДАНІ — ТВОЇ
Геолокація обробляється лише на пристрої і лише під час поїздки наземними ділянками. Застосунок нічого не збирає, не передає і не зберігає поза твоїм телефоном.

ДЛЯ ТИХ, ХТО ХОЧЕ ТОЧНІШЕ
Режим калібрування дозволяє заміряти реальні часи перегонів своєї лінії — розрахунки стануть точнішими саме для твоїх маршрутів. Журнал поїздок показує, наскільки план збігся з фактом.

Всі 52 станції трьох ліній київського метрополітену. Зроблено в Україні.

## Ключові слова (до 100 символів)
метро,київ,таймер,станція,зупинка,поїздка,пересадка,офлайн,підземка,метрополітен,будильник,dynamic

## Категорії
- Основна: Навігація (Navigation)
- Додаткова: Подорожі (Travel)

## Вікове обмеження
4+

## Що нового (версія 1.0)
Перший реліз: зворотний відлік у Dynamic Island та на екрані блокування, сповіщення за одну зупинку до виходу, пересадки між лініями, GPS-уточнення на наземних ділянках, режим калібрування та журнал поїздок. Повністю офлайн.

## Конфіденційність (App Privacy у App Store Connect)
- **Data Not Collected / Дані не збираються** — застосунок не збирає жодних даних.
- Геолокація: використовується тільки локально (When In Use), нікуди не передається, тому в анкеті App Privacy позначається як «не збирається» (data is not transmitted off device).
- URL політики конфіденційності: розмістити вміст `PRIVACY.md` (наприклад, GitHub Pages) і вказати посилання.

## Скриншоти для App Store Connect
Готові слайди — `screenshots/framed/` (1320×2868, генеруються
`Scripts/make_store_frames.py` із сирих скринів у `screenshots/`).
Завантажувати в цьому порядку (перші три видно в пошуку):
1. `store_1_trip.png` — «Не проспи свою станцію» (поїздка + банер сповіщення)
2. `store_2_island.png` — «Відлік у Dynamic Island» (збільшений острів)
3. `store_3_pick.png` — «Обери станції — і поїхали»
4. `store_4_transfer.png` — «Пересадки будує сам»
5. `store_5_offline.png` — «Нуль реклами. Нуль трекінгу. Нуль мережі.»

## Поля App Store Connect, які легко забути

- **Copyright:** `2026 Vladyslav Domotskyi`
  (поле в App Information; формат — рік + правовласник, без слова «Copyright»)
- **Контакт для App Review** (не публікується, потрібен рев'юверу):
  Vladyslav Domotskyi, vladdomotsky@gmail.com, телефон — вказати свій
- **Демо-акаунт:** не потрібен, у застосунку немає входу й реєстрації
  (у формі так і написати: «No account required»)
- **Marketing URL:** необов'язково; можна вказати ту саму
  https://dayvan777.github.io/METRO/
- **Локалізації лістингу:** українська (основна) + англійська
  (тексти — `metadata_uk.md` і `metadata_en.md`)
- **Регіони продажу:** якщо не заявлятися як трейдер DSA — виключити ЄС
- **Ціна:** безкоштовно, без покупок у застосунку

## Нотатки для рев'ювера (англійською — для App Review)
Metro Timer is an offline countdown timer for the Kyiv metro. To test without
being in Kyiv: pick any departure and destination station, tap «Поїхали» (Go),
allow notifications — a Live Activity appears with a countdown computed from
per-segment travel times taken from the operator's official open-data timetable.
Notifications fire one stop before arrival and at arrival.

No account and no data collection. Location permission is optional: it is used
only in the foreground on above-ground segments to auto-correct the estimate;
the app is fully functional if denied.

NETWORK: the app makes exactly one kind of network request, and only if the user
turns on the "Показувати тривоги в Києві" (Show air-raid alerts in Kyiv) switch
in the About screen — it is OFF by default, so the reviewer will see no network
traffic unless it is enabled. When on, the app performs a parameterless GET to a
public feed of regional air-raid statuses (ubilling.net.ua/aerialalerts/) once a
minute while the app is in the foreground, and shows a banner if Kyiv is under
alert. Nothing is uploaded: no identifiers, no routes, no user data. There is no
background mode, no push, no server of ours. The About screen states plainly that
the feed is unofficial and must not be relied on for safety, and when the feed is
unreachable the app displays "не вдалося перевірити" ("could not check") instead
of implying that there is no alert.

App Privacy is declared as "Data Not Collected": nothing the app sends can
identify the user, and nothing is stored off device. Local files (trip journal,
calibration) are encrypted and excluded from iCloud/iTunes backups.

## Перед відправленням (чек-лист)

Готове:
- [x] Політика конфіденційності за публічним URL — https://dayvan777.github.io/METRO/
      (той самий URL іде і в Support URL; сторінка двомовна)
- [x] Версія/білд: MARKETING_VERSION 1.0, CURRENT_PROJECT_VERSION 1
- [x] Скриншоти 6.9" (1320×2868) — 5 слайдів у `screenshots/framed/`, зняті
      17.08.2026 з поточного інтерфейсу (реальні кадри, реальне сповіщення,
      реальний Dynamic Island)
- [x] `ITSAppUsesNonExemptEncryption = false` — анкета експортного контролю
- [x] PrivacyInfo.xcprivacy в обох таргетах
- [x] Нотатки рев'юверу описують мережевий виклик тривог чесно
- [x] Локальні файли зашифровані й виключені з резервних копій

Потребує платного акаунта:
- [ ] Платний акаунт Apple Developer Program ($99/рік) — Personal Team не публікує
- [ ] Bundle ID зареєструвати в App Store Connect (ua.vlad.MetroTimer)
- [ ] Повернути time-sensitive entitlement: `MT_PAID_TEAM=1 python3 Scripts/gen_pbxproj.py`
      (без нього iOS мовчки знижує рівень сповіщень, і «Наступна — ваша»
      не пробиває режими фокусування — див. `docs/READINESS.md`)
- [ ] Увімкнути звіти про збої в Xcode Organizer (без SDK і без збору даних)
- [ ] Archive → Distribute у Xcode (схема MetroTimer, Any iOS Device)

Відповіді на анкети App Store Connect:
- **App Privacy: Data Not Collected.** Застосунок нічого не надсилає, що
  ідентифікує користувача, і нічого не зберігає поза пристроєм. IP-адресу
  бачить сервер фіду тривог так само, як будь-який сайт; ми її не отримуємо
  і не зберігаємо — під визначення збору Apple це не підпадає.
- **Віковий рейтинг:** 4+.
- **Статус трейдера DSA:** потрібен для ЄС. Для фізособи це окрема морока;
  Україна не ЄС, тож можна не заявлятися і виключити ЄС із регіонів продажу.

Залишається полевою перевіркою (не закривається кодом):
- [ ] 5–10 поїздок трьома лініями: медіана |план − факт| на кінцевій ≤ 30 с
- [ ] Заміряти два перевірені переходи: Театральна ↔ Золоті ворота і
      Площа Українських Героїв ↔ Палац спорту (зараз там оцінка, не замір)
