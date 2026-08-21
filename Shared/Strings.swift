import Foundation

// Украинский и английский — парами в одной строке: рассинхронизировать
// невозможно, ревью занимает один взгляд. Выбор языка — Localization.swift.
enum L10n {
    static var appTitle: String { tr("Метро-таймер", "Metro Timer") }
    static var go: String { tr("Поїхали", "Start") }
    static var stopTrip: String { tr("Зупинити", "Stop") }
    static var recents: String { tr("Останні поїздки", "Recent trips") }
    static var calibration: String { tr("Калібрування", "Calibration") }
    static var pickOrigin: String { tr("Оберіть станцію відправлення", "Choose your departure station") }
    static var pickDestination: String { tr("Тепер оберіть станцію призначення", "Now choose your destination") }
    static var pickReady: String { tr("Маршрут готовий", "Route ready") }
    static var closedStation: String { tr("проїзд без зупинки", "passed without stopping") }
    static var minusStop: String { tr("−1 зупинка", "−1 stop") }
    static var plusStop: String { tr("+1 зупинка", "+1 stop") }
    static var reset: String { tr("Скинути", "Reset") }
    static var done: String { tr("Готово", "Done") }

    // Ключевой контракт продукта: отсчёт стартует от момента отправления поезда.
    static var startHint: String { tr("Натисніть, коли поїзд рушить", "Tap when the train starts moving") }
    static func routePreview(_ from: String, to: String) -> String { "\(from) → \(to)" }
    static func routeMinutes(_ minutes: Int) -> String { "~\(minutes) \(tr("хв", "min"))" }
    static func routeTransfer(_ station: String) -> String {
        tr("пересадка: \(station)", "change at \(station)")
    }
    static var swapStations: String { tr("Поміняти місцями", "Swap stations") }
    // Реальность 2026: во время тревоги наземными участками поезда не ходят.
    static var surfaceAlertWarning: String {
        tr("Маршрут має наземну ділянку: під час повітряної тривоги поїзди там не курсують, і відлік може відставати.",
           "This route has an above-ground section: trains do not run there during an air-raid alert, so the countdown may fall behind.")
    }
    static var routeSuspended: String {
        tr("Рух цією ділянкою тимчасово припинено", "Service on this section is suspended")
    }

    // Часы работы по официальному расписанию (проверяются и для пересадки).
    static func serviceFirstTrain(_ station: String, time: String) -> String {
        tr("Метро ще зачинене: перший поїзд з «\(station)» — о \(time)",
           "The metro is still closed: first train from \(station) at \(time)")
    }
    static func serviceMissedLast(_ station: String, time: String) -> String {
        tr("Останній поїзд у цей бік з «\(station)» вирушив о \(time)",
           "The last train this way from \(station) left at \(time)")
    }
    static func serviceLastSoon(_ station: String, time: String) -> String {
        tr("Останній поїзд у цей бік з «\(station)» — о \(time)",
           "Last train this way from \(station) at \(time)")
    }

    // Пересадка: ожидание поезда — самое неопределённое место расчёта.
    static var transferWaitHint: String {
        tr("Чекаєте поїзд? Час очікування — приблизний, за розкладом.",
           "Waiting for the train? The wait is an estimate from the timetable.")
    }
    static var transferWaitLate: String {
        tr("Поїзд ще не рушив? Натисніть ще раз, коли рушить.",
           "Train still not moving? Tap again when it does.")
    }
    static var transferBoarded: String { tr("Поїзд рушив", "Train started") }

    // Воздушные тревоги (единственная сетевая функция, включается вручную).
    static var alertsTitle: String { tr("Повітряні тривоги", "Air-raid alerts") }
    static var alertsToggle: String { tr("Показувати тривоги в Києві", "Show air-raid alerts in Kyiv") }
    static var alertsToggleNote: String {
        tr("Єдина функція, якій потрібен інтернет: застосунок раз на хвилину перевіряє статус тривоги в Києві, поки відкритий. Це звичайний запит без параметрів — ні маршрут, ні будь-які ваші дані не передаються. Як і будь-якому сайту, серверу видно вашу IP-адресу.",
           "The only feature that needs the internet: while open, the app checks the Kyiv alert status once a minute. It is a plain request with no parameters — neither your route nor any of your data is sent. As with any website, the server sees your IP address.")
    }
    // Джерело неофіційне: сказати про це треба до того, як людина почне
    // покладатися на банер у питанні власної безпеки.
    static var alertsSourceWarning: String {
        tr("Джерело — публічний фід, не офіційний канал оповіщення. Він може відставати, помилятися або бути недоступним. Не покладайтеся на цей застосунок у питаннях безпеки: користуйтеся офіційними застосунками тривог і сиренами.",
           "The source is a public feed, not an official alert channel. It can lag, be wrong, or be unavailable. Do not rely on this app for safety decisions: use the official alert apps and sirens.")
    }
    static var alertsUnavailable: String {
        tr("Не вдалося перевірити: статус невідомий", "Could not check: status unknown")
    }
    static var alertsActive: String { tr("Повітряна тривога в Києві", "Air-raid alert in Kyiv") }
    static var alertsActiveTrip: String {
        tr("Повітряна тривога: наземними ділянками поїзди не курсують, відлік може відставати",
           "Air-raid alert: trains do not run on above-ground sections, the countdown may fall behind")
    }
    static var alertsQuiet: String { tr("Тривоги немає", "No alert") }
    static var alertsUnknown: String { tr("Статус невідомий", "Status unknown") }
    static var alertNotifTitle: String { tr("Повітряна тривога в Києві", "Air-raid alert in Kyiv") }
    static var alertNotifBody: String {
        tr("Наземними ділянками поїзди не курсують — відлік може відставати.",
           "Trains do not run on above-ground sections — the countdown may fall behind.")
    }
    static func alertsUpdated(_ time: String) -> String {
        tr("оновлено о \(time)", "updated at \(time)")
    }

    // Одноразовая карточка при первом запуске.
    static var onboardingTitle: String { tr("Як це працює", "How it works") }
    static var onboardingStep1: String {
        tr("Оберіть станцію відправлення і станцію призначення.",
           "Choose your departure station and your destination.")
    }
    static var onboardingStep2: String {
        tr("Натисніть «Поїхали» в момент, коли поїзд рушить зі станції — не раніше.",
           "Tap “Start” the moment the train pulls out of the station — not before.")
    }
    static var onboardingStep3: String {
        tr("За одну зупинку до виходу телефон завібрує. Розрахунок орієнтовний: якщо поїзд затримався — натисніть «+1 зупинка».",
           "One stop before yours the phone will vibrate. The estimate is approximate: if the train is running late, tap “+1 stop”.")
    }
    static var onboardingGotIt: String { tr("Зрозуміло", "Got it") }

    static var correctionTitle: String { tr("Порахувалось невірно?", "Count looks wrong?") }
    static var stopConfirmTitle: String { tr("Зупинити поїздку?", "Stop the trip?") }
    static var stopConfirmBody: String {
        tr("Відлік і сповіщення про вихід буде скасовано.",
           "The countdown and the exit notification will be cancelled.")
    }
    static var stopConfirmAction: String { tr("Зупинити поїздку", "Stop the trip") }
    // Отдельная ветка для «вышел раньше расчёта». Без неё ранние прибытия
    // попадали в журнал как «бросил поездку» — а это ровно та сторона ошибки,
    // где предупреждение приходит после нужной станции.
    static var stopConfirmArrived: String { tr("Я вже вийшов", "I already got off") }
    static var stopConfirmKeep: String { tr("Продовжити поїздку", "Keep going") }
    static var arrivedAction: String { tr("Я на місці", "I’m here") }

    // VoiceOver.
    static func a11yLine(_ id: String) -> String {
        tr("Лінія \(id.uppercased())", "Line \(id.uppercased())")
    }
    static var a11yOrigin: String { tr("станція відправлення", "departure station") }
    static var a11yDestination: String { tr("станція призначення", "destination station") }
    static var a11yMinusHint: String {
        tr("Поїзд випереджає розрахунок: на одну зупинку менше",
           "The train is ahead of the estimate: one stop fewer")
    }
    static var a11yPlusHint: String {
        tr("Поїзд відстає: на одну зупинку більше", "The train is behind: one stop more")
    }
    static var a11yRecentHint: String {
        tr("Підставити станції цієї поїздки", "Fill in the stations of this trip")
    }
    static func a11yStopsLeft(_ n: Int) -> String {
        tr("Залишилось \(n) \(stopsWord(n))", "\(n) \(stopsWord(n)) left")
    }
    static var a11yPassed: String { tr("пройдено", "passed") }
    static var a11yNext: String { tr("наступна", "next") }

    static var notifExplainTitle: String { tr("Потрібні сповіщення", "Notifications needed") }
    static var notifExplainBody: String {
        tr("Щоб попередити вас за одну зупинку до виходу — навіть коли застосунок закрито — потрібен дозвіл на сповіщення.",
           "To warn you one stop before yours — even when the app is closed — notification permission is needed.")
    }
    static var notifContinue: String { tr("Дозволити сповіщення", "Allow notifications") }
    static var notifSkip: String { tr("Продовжити без сповіщень", "Continue without notifications") }
    static var cancel: String { tr("Скасувати", "Cancel") }
    static var notifDenied: String {
        tr("Сповіщення вимкнені: попередження про вихід не прийдуть.",
           "Notifications are off: you won’t get the exit warning.")
    }
    static var openSettings: String { tr("Налаштування", "Settings") }
    // «Живі активності» выключены системным тумблером: ни острова, ни карточки
    // на экране блокировки — молчать об этом нельзя, это весь смысл продукта.
    static var liveActivityOff: String {
        tr("Живі активності вимкнені: відліку на екрані блокування не буде.",
           "Live Activities are off: there will be no countdown on the Lock Screen.")
    }

    static var notifNextBody: String { tr("Готуйтеся до виходу.", "Get ready to exit.") }
    static var notifArrivalBody: String { tr("Виходьте.", "This is your stop.") }
    static func notifNextTitle(_ station: String) -> String {
        tr("Наступна — \(station).", "Next stop: \(station).")
    }
    static func notifTransferBody(_ station: String) -> String {
        tr("Пересадка: перейдіть на «\(station)».", "Change here: walk to \(station).")
    }

    static func transferRow(_ station: String, minutes: Int) -> String {
        tr("Пересадка на «\(station)» · ~\(minutes) хв",
           "Change to \(station) · ~\(minutes) min")
    }
    static var about: String { tr("Про застосунок", "About") }
    static var aboutMenu: String { tr("Ще", "More") }
    static var aboutDisclaimer: String {
        tr("Неофіційний застосунок. Не пов'язаний з КП «Київський метрополітен» та КМДА.",
           "Unofficial app. Not affiliated with Kyiv Metro or the Kyiv City Administration.")
    }
    static var aboutHowTitle: String { tr("Як це працює", "How it works") }
    static var aboutHowBody: String {
        tr("Оберіть станції та натисніть «Поїхали» в момент, коли поїзд рушить зі станції — не раніше. Застосунок розраховує час до кожної зупинки за офіційним графіком метрополітену і за одну зупинку до виходу надішле сповіщення з вібрацією. Розрахунок орієнтовний (±1 хв): якщо поїзд затримався — натисніть «+1 зупинка».",
           "Choose your stations and tap “Start” the moment the train pulls out — not before. The app works out the time to every stop from the metro’s official timetable and sends a notification with vibration one stop before yours. The estimate is approximate (±1 min): if the train is running late, tap “+1 stop”.")
    }
    static var aboutDataTitle: String { tr("Джерела даних", "Data sources") }
    static var aboutDataBody: String {
        tr("Часи перегонів, інтервали руху та перший/останній поїзд — офіційний графік КП «Київський метрополітен» (Портал відкритих даних Києва, серпень 2026). Координати станцій — © OpenStreetMap contributors, ліцензія ODbL. Розклад може змінюватися; звіряйтеся з табло на станції.",
           "Running times, service intervals and first/last train — the official Kyiv Metro timetable (Kyiv Open Data Portal, August 2026). Station coordinates — © OpenStreetMap contributors, ODbL licence. Timetables change; check the display at the station.")
    }
    static let aboutOSMLink = "openstreetmap.org/copyright"
    static var aboutPrivacyTitle: String { tr("Конфіденційність", "Privacy") }
    static var aboutPrivacyBody: String {
        tr("За замовчуванням застосунок працює повністю офлайн: жодних мережевих запитів, реклами, аналітики та сторонніх SDK (єдиний виняток — увімкнені вами тривоги). Усе, що він зберігає (журнал поїздок, калібрування, у режимі калібрування — записи акселерометра й геопозиції), лежить лише на вашому пристрої і залишає його тільки через кнопку «Експортувати» за вашим рішенням. Геолокація використовується лише коли застосунок відкритий. Дані не потрапляють у резервні копії. Повний текст політики — нижче.",
           "By default the app works fully offline: no network requests, ads, analytics or third-party SDKs (the only exception is air-raid alerts, if you turn them on). Everything it stores (trip journal, calibration, and in Calibration mode accelerometer and location recordings) stays on your device and leaves it only through the “Export” button, at your decision. Location is used only while the app is open. The data is kept out of backups. The full policy is below.")
    }
    static var aboutPrivacyFull: String { tr("Політика конфіденційності", "Privacy Policy") }
    static var aboutDeleteJournal: String { tr("Видалити журнал поїздок", "Delete trip journal") }
    static var aboutDeleteCalibration: String { tr("Видалити дані калібрування", "Delete calibration data") }
    static var aboutDeleteConfirm: String {
        tr("Дані буде видалено з пристрою без можливості відновлення.",
           "The data will be deleted from the device and cannot be recovered.")
    }
    static var aboutDelete: String { tr("Видалити", "Delete") }
    static var aboutContact: String { tr("Написати розробнику", "Contact the developer") }
    static var aboutVersion: String { tr("Версія", "Version") }

    // Политика конфиденциальности — тот же текст, что в AppStore/PRIVACY.md.
    static var privacyPolicySections: [(title: String, body: String)] {
        [
            ("", tr("Оновлено: серпень 2026. Розробник: Владислав Домоцький, vladdomotsky@gmail.com.",
                    "Updated: August 2026. Developer: Vladyslav Domotskyi, vladdomotsky@gmail.com.")),
            (tr("Коротко", "In short"),
             tr("«Метро-таймер» не збирає і не передає жодних ваших даних. Усе, що застосунок зберігає, залишається на вашому пристрої.",
                "Metro Timer does not collect or transmit any of your data. Everything the app stores stays on your device.")),
            (tr("Мережа", "Network"),
             tr("За замовчуванням застосунок працює повністю офлайн і не робить жодних мережевих запитів. Єдиний виняток — перемикач «Показувати тривоги в Києві» (вимкнений за замовчуванням): якщо ви його увімкнете, застосунок раз на хвилину — і лише поки відкритий — запитує публічний фід статусів повітряних тривог по областях. Це звичайний запит без параметрів: ні ваших даних, ні ідентифікаторів, ні маршрутів застосунок не надсилає. Як і при відкритті будь-якого сайту, серверу фіду видно вашу IP-адресу і час запиту — ми цим не керуємо і нічого звідти не отримуємо. Джерело неофіційне і може бути недоступним; тоді застосунок прямо каже «не вдалося перевірити», а не мовчить. Реклами, аналітики, трекерів і сторонніх SDK немає.",
                "By default the app is fully offline and makes no network requests. The only exception is the “Show air-raid alerts in Kyiv” switch (off by default): when enabled, the app queries a public feed of regional air-raid statuses once a minute, and only while the app is open. It is a plain request with no parameters — the app sends none of your data, identifiers or routes. As when you open any website, the feed’s server sees your IP address and the time of the request — we do not control that and receive nothing from it. The source is unofficial and can be unavailable; in that case the app says “could not check” outright instead of staying silent. No ads, analytics, trackers or third-party SDKs.")),
            (tr("Геолокація", "Location"),
             tr("Використовується лише коли застосунок відкритий (дозвіл «Під час використання»). Під час поїздки — тільки на наземних ділянках метро, щоб уточнити розрахункове положення поїзда; координати обробляються на пристрої і не зберігаються. У режимі калібрування, який ви вмикаєте вручну, усі отримані координати (у тому числі приблизні, під землею) записуються у файл на пристрої разом із часом — це трек вашої поїздки. У фоні геолокація не використовується. Без дозволу на геолокацію застосунок повністю функціональний.",
                "Used only while the app is open (“While Using” permission). During a trip — only on above-ground metro sections, to refine the train’s estimated position; coordinates are processed on device and not stored. In the manually enabled Calibration mode, all received coordinates (including approximate ones underground) are written to a file on the device together with timestamps — a track of your ride. Location is never used in the background. The app is fully functional without location permission.")),
            (tr("Дані руху", "Motion data"),
             tr("Акселерометр записується лише в режимі калібрування. Записи зберігаються у файлах застосунку на пристрої.",
                "The accelerometer is recorded only in Calibration mode; the files stay on the device.")),
            (tr("Сповіщення", "Notifications"),
             tr("Плануються локально на пристрої для попередження про вихід.",
                "Scheduled locally on the device to warn you before your stop.")),
            (tr("Журнал поїздок і калібрування", "Trip journal and calibration"),
             tr("Зберігаються локально у сховищі застосунку і навмисно виключені з резервних копій iCloud та iTunes — вони живуть тільки на цьому пристрої (тому при переїзді на новий телефон не переносяться). Файли залишають пристрій лише якщо ви самі експортуєте їх кнопкою «Експортувати», і ви бачите список та розмір того, що експортуєте (файл калібрування містить трек поїздки з часом). Видалити дані можна кнопками на екрані «Про застосунок» або видаливши застосунок; відкликати доступ до геолокації — у Параметрах iOS.",
                "Stored locally and deliberately excluded from iCloud and iTunes backups — they live on this device only (so they do not carry over to a new phone). Files leave the device only if you export them yourself with the “Export” button, and you see the list and size of what you export (a calibration file contains a timestamped ride track). You can delete the data from the “About” screen or by deleting the app; location access can be revoked in iOS Settings.")),
            (tr("Діти", "Children"),
             tr("Застосунок не збирає даних ні від кого, включно з дітьми.",
                "The app collects no data from anyone, including children.")),
            (tr("Зміни політики", "Policy changes"),
             tr("У разі змін оновлена політика публікуватиметься за тією ж адресою і в застосунку.",
                "If the policy changes, the updated version will be published at the same address and in the app.")),
        ]
    }

    static var journal: String { tr("Журнал", "Journal") }
    static var journalEmpty: String { tr("Поїздок ще не було", "No trips yet") }
    static var journalExport: String { tr("Експортувати журнал", "Export journal") }
    static var journalFinished: String { tr("завершено", "completed") }
    static var journalStopped: String { tr("зупинено", "stopped") }
    static var journalArrived: String { tr("підтверджено", "confirmed") }

    // Точность считается только по поездкам, где пассажир сам подтвердил
    // прибытие: всё остальное — сравнение плана с планом.
    static func journalAccuracy(_ seconds: Int, trips: Int) -> String {
        tr("Похибка розрахунку: медіана \(signedSeconds(seconds)) на \(trips) \(tripsWord(trips))",
           "Estimate error: median \(signedSeconds(seconds)) over \(trips) \(tripsWord(trips))")
    }
    static var journalAccuracyHint: String {
        tr("Щоб цифра з'явилась, натискайте «Я на місці», коли вийдете: лише тоді застосунок знає реальний час прибуття.",
           "To get this number, tap “I'm here” when you get off: that is the only moment the app learns the real arrival time.")
    }
    static func signedSeconds(_ seconds: Int) -> String {
        let sign = seconds > 0 ? "+" : (seconds < 0 ? "−" : "")
        return tr("\(sign)\(abs(seconds)) с", "\(sign)\(abs(seconds)) s")
    }
    static func tripsWord(_ n: Int) -> String {
        guard appLanguage == .uk else { return n == 1 ? "trip" : "trips" }
        let mod100 = n % 100
        if (11...14).contains(mod100) { return "поїздках" }
        return n % 10 == 1 ? "поїздці" : "поїздках"
    }
    static var journalPlanned: String { tr("план", "planned") }
    static var journalActual: String { tr("підсумок", "actual") }
    static var routeError: String { tr("Не вдалося побудувати маршрут", "Could not build a route") }

    static var calibStart: String { tr("Старт", "Start") }
    static var calibFinish: String { tr("Завершити", "Finish") }
    static var calibExport: String { tr("Експортувати", "Export") }
    static var calibExportTitle: String { tr("Що експортувати", "What to export") }
    static var calibExportTimes: String { tr("Заміряні часи перегонів", "Measured running times") }
    static var calibExportEmpty: String { tr("Ще нема що експортувати", "Nothing to export yet") }
    static func calibExportSelected(_ bytes: Int64) -> String {
        // Нічого не вибрано — розмір не має сенсу («Нуль КБ» виглядає як помилка).
        guard bytes > 0 else { return calibExport }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return tr("Експортувати вибране (\(size))", "Export selected (\(size))")
    }
    static var calibStopped: String { tr("Поїзд зупинився", "Train stopped") }
    static var calibDeparted: String { tr("Поїзд рушив", "Train started") }
    static var calibLine: String { tr("Лінія", "Line") }
    static var calibDirection: String { tr("Напрямок", "Direction") }
    static var calibFrom: String { tr("Поточна станція", "Current station") }
    static var calibHint: String {
        tr("Натисніть «Старт» у момент відправлення. Далі тисніть кнопку щоразу, коли поїзд зупинився і коли рушив.",
           "Tap “Start” the moment the train departs. After that, tap the button every time the train stops and every time it starts.")
    }

    // Журнал калибровки — инструмент разработчика, но читать его должно быть
    // можно на том же языке, что и остальное приложение.
    static func calibLogTravel(_ station: String, seconds: Int, skipped: Bool) -> String {
        let line = tr("\(station): хід \(seconds) с", "\(station): run \(seconds) s")
        return skipped ? line + tr(" — пропущено", " — skipped") : line
    }
    static func calibLogDwell(_ station: String, seconds: Int, skipped: Bool) -> String {
        let line = tr("\(station): стоянка \(seconds) с", "\(station): dwell \(seconds) s")
        return skipped ? line + tr(" — пропущено", " — skipped") : line
    }

    static var arrived: String { tr("Ви на місці?", "Are you there?") }
    static func overdue(_ time: String) -> String {
        tr("Мали прибути о \(time)", "Expected arrival was \(time)")
    }
    static var overdueHint: String {
        tr("Ще їдете? Натисніть «+1 зупинка»", "Still riding? Tap “+1 stop”")
    }
    static var nextStationPrefix: String { tr("Наступна: ", "Next: ") }
    static var lastStopAhead: String { tr("Наступна — ваша", "Yours is next") }

    // Live Activity: в острове места мало, поэтому свои короткие подписи.
    static var activityArrived: String { tr("Прибули", "You’re here") }
    static var islandMinus: String { tr("−1 зуп.", "−1 stop") }
    static var islandPlus: String { tr("+1 зуп.", "+1 stop") }

    // «Ще N зупинок» — без согласования глагола и короче для острова.
    static func stopsRemaining(_ n: Int) -> String {
        tr("Ще \(n) \(stopsWord(n))", "\(n) \(stopsWord(n)) to go")
    }

    static func stopsWord(_ n: Int) -> String {
        guard appLanguage == .uk else { return n == 1 ? "stop" : "stops" }
        let mod100 = n % 100
        if (11...14).contains(mod100) { return "зупинок" }
        switch n % 10 {
        case 1: return "зупинка"
        case 2...4: return "зупинки"
        default: return "зупинок"
        }
    }
}
