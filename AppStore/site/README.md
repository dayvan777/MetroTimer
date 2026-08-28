# Сторінка застосунку: лендинг + політика конфіденційності + підтримка

Одна сторінка `index.html` (+ тека `img/` зі скриншотами й бейджем App Store)
закриває три ролі: лендинг із кнопкою «Завантажити в App Store», **Privacy
Policy URL** і **Support URL** для App Store Connect. Політика лишається за
тією самою адресою (якір `#privacy`), тож URL у App Store Connect не змінюється.

Опубліковано: https://dayvan777.github.io/METRO/ (репозиторій `dayvan777/METRO`,
гілка `main`, деплой — GitHub Pages з кореня). Оновлення: скопіювати `index.html`
і `img/` у той репозиторій і запушити.

## Як опублікувати (5 хвилин, через сайт GitHub)

1. Зайти на [github.com](https://github.com), увійти (або зареєструватися — безкоштовно).
2. Праворуч угорі **+** → **New repository**.
   - Repository name: `metro-timer`
   - Обрати **Public**
   - **Create repository**
3. На сторінці репозиторію: **Add file** → **Upload files**.
   Перетягнути три файли з теки `MetroTimer/AppStore/site/`:
   `index.html`, `icon.png`, `favicon.png` → **Commit changes**.
4. Вкладка **Settings** → зліва **Pages** → у блоці *Build and deployment*:
   Source = **Deploy from a branch**, Branch = **main**, тека = **/ (root)** → **Save**.
5. Через 1–2 хвилини оновити сторінку Pages — вона покаже адресу виду
   `https://<логін>.github.io/metro-timer/`. Це і є URL для App Store Connect.

## Куди вставити адресу

В App Store Connect → застосунок → **App Information**:
- **Privacy Policy URL** — адреса зі стану 5
- **Support URL** — та сама адреса (на сторінці є розділ «Підтримка» з поштою)

Плюс вписати її в `AppStore/metadata_uk.md` (поле «URL політики»), щоб не шукати вдруге.

## Оновлення тексту

Текст політики живе у трьох місцях і має збігатися:
`AppStore/PRIVACY.md` (джерело), `Shared/Strings.swift` (офлайн-копія в застосунку,
`privacyPolicySections`) і цей `index.html`. Змінюючи одне — оновіть решту.
