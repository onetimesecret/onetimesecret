---
title: Руководство по переводу на русский язык
description: Комплексное руководство по переводу Onetime Secret на русский язык, объединяющее глоссарий терминов и языковые заметки
---

# Translation Guidance for Russian

This document provides comprehensive guidance for translating Onetime Secret content. It combines universal translation resources with locale-specific terminology and rules.

## Universal Translation Resources

Before translating, review these cross-language guidelines that apply to all locales:

- **[Translating "Secret"](/en/translations/universal/secret-concept)** - How to handle the word "secret" across different language contexts
- **[Password vs. Passphrase](/en/translations/universal/password-passphrase)** - Maintaining the critical distinction between account passwords and secret passphrases
- **[Voice and Tone](/en/translations/universal/voice-and-tone)** - Patterns for active vs. passive voice, formality levels, and cultural adaptations
- **[Brand Terms](/en/translations/universal/brand-terms)** - Terms that should not be translated (product names, tier names)
- **[Quality Checklist](/en/translations/universal/quality-checklist)** - Comprehensive checklist for pre-submission review

---

## Глоссарий

# Глоссарий перевода Onetime Secret

Этот глоссарий предоставляет стандартизированные переводы ключевых терминов для обеспечения согласованности в приложении Onetime Secret. Разработан в соответствии с рекомендациями по переводу и потребностями русского языка.

> **Стандартный русский язык:** Используйте стандартный письменный русский (литературный язык), как в крупных русскоязычных технологических продуктах. Это обеспечивает понятность для всех русскоязычных пользователей.

## Основная терминология

| English | Русский (RU) | Альтернативы | Context |
|---------|--------------|--------------|---------|
| secret (noun) | секрет | ~~тайна~~ | Основная концепция приложения. **Используйте «секрет»** — более нейтральный технический термин. «Тайна» имеет личный/эмоциональный оттенок. |
| secret (adj) | секретный | безопасный | Прилагательное для описания защищённого содержимого |
| passphrase | кодовая фраза | фраза-пароль | Метод аутентификации для секретов. Чётко отличается от «пароля» (для учётных записей). |
| burn (verb) | уничтожить | ~~сжечь~~ | Действие удаления секрета до просмотра. **Используйте «уничтожить»** — естественнее в цифровом контексте. Буквальный перевод «сжечь» неуместен. |
| burn (status) | уничтожен | удалён | Статус после уничтожения |
| view/reveal | просмотреть/раскрыть | показать | Действие доступа к секрету |
| link | ссылка | — | URL, позволяющий получить доступ к секрету |
| encrypt/encrypted | шифровать/зашифрованный | — | Метод безопасности. Не путать с «кодировать» (encoding). |
| secure | безопасный | защищённый | Состояние защиты |

## Элементы пользовательского интерфейса

| English | Русский (RU) | Альтернативы | Context |
|---------|--------------|--------------|---------|
| Share a secret | Поделиться секретом | — | Основное действие |
| Create Account | Создать аккаунт | учётную запись | Регистрация. «Аккаунт» — современный вариант, «учётная запись» — формальный. Оба приемлемы, выбирайте один и придерживайтесь его. |
| Sign In | Войти | — | Аутентификация |
| Dashboard | Панель управления | Аккаунт | Главная страница пользователя |
| Settings | Настройки | Параметры | Страница конфигурации |
| Privacy Options | Параметры конфиденциальности | Настройки приватности | Настройки секретов |
| Feedback | Обратная связь | Отзыв | Комментарии пользователей |
| Get Started | Начать | Приступить | Призыв к действию |
| Loading... | Загрузка... | — | Состояние ожидания |
| Processing... | Обработка... | — | Состояние выполнения |

## Термины состояния

| English | Русский (RU) | Род | Context |
|---------|--------------|-----|---------|
| received | получен | м. | Секрет был просмотрен (согласование с «секрет») |
| burned | уничтожен | м. | Секрет удалён до просмотра (согласование с «секрет») |
| destroyed | удалён | м. | Секрет безвозвратно удалён |
| expired | истёк | м. | Секрет больше недоступен из-за времени |
| created | создан | м. | Секрет был создан |
| new | новый | м. | Новый секрет |
| viewed | просмотрен | м. | Ссылка была открыта |
| active | активен | м. | Секрет доступен |
| inactive | неактивен | м. | Секрет недоступен |
| copied | скопировано | ср. | Содержимое скопировано (согласование с «содержимое») |

## Термины, связанные со временем

| English | Русский (RU) | Context |
|---------|--------------|---------|
| expires in | истекает через | Время до недоступности секрета |
| day/days | день/дня/дней | Единица времени (1/2-4/5+) |
| hour/hours | час/часа/часов | Единица времени (1/2-4/5+) |
| minute/minutes | минута/минуты/минут | Единица времени (1/2-4/5+) |
| second/seconds | секунда/секунды/секунд | Единица времени (1/2-4/5+) |

## Функции безопасности

| English | Русский (RU) | Context |
|---------|--------------|---------|
| one-time access | одноразовый доступ | Основная функция безопасности |
| passphrase protection | защита кодовой фразой | Дополнительная безопасность |
| encrypted in transit | зашифровано при передаче | Метод защиты данных |
| encrypted at rest | зашифровано при хранении | Защита хранения |

## Термины, связанные с учётной записью

| English | Русский (RU) | Альтернативы | Context |
|---------|--------------|--------------|---------|
| email | электронная почта | — | Идентификатор пользователя |
| password | пароль | — | Аутентификация учётной записи |
| account | учётная запись | аккаунт | Профиль пользователя. Оба варианта приемлемы, выбирайте один и придерживайтесь его. |
| subscription | подписка | — | Платная услуга |
| customer | клиент | — | Платящий пользователь |

## Термины, связанные с доменом

| English | Русский (RU) | Context |
|---------|--------------|---------|
| custom domain | пользовательский домен | Премиум-функция |
| domain verification | проверка домена | Процесс настройки |
| DNS record | DNS-запись | Конфигурация |
| CNAME record | CNAME-запись | DNS-конфигурация |

## Сообщения об ошибках

| English | Русский (RU) | Context |
|---------|--------------|---------|
| error | ошибка | Уведомление о проблемах |
| warning | предупреждение | Предупреждающее уведомление |
| oops | упс | Дружественное введение к ошибке |

## Кнопки и действия

| English | Русский (RU) | Context |
|---------|--------------|---------|
| submit | отправить | Действие формы |
| cancel | отменить | Негативное действие |
| confirm | подтвердить | Позитивное действие |
| copy to clipboard | копировать в буфер обмена | Вспомогательное действие |
| continue | продолжить | Навигация |
| back | назад | Навигация |

## Маркетинговые термины

| English | Русский (RU) | Context |
|---------|--------------|---------|
| secure links | безопасные ссылки | Функция продукта |
| privacy-first design | дизайн, ориентированный на конфиденциальность | Философия дизайна |
| custom branding | персонализированный брендинг | Премиум-функция |

## Рекомендации по переводу

1. **Согласованность**: Использовать один и тот же перевод термина во всём приложении
2. **Контекст**: Учитывать, как термин используется в приложении
3. **Культурная адаптация**: Адаптировать термины к местным соглашениям при необходимости
4. **Техническая точность**: Обеспечить точный перевод терминов безопасности
5. **Тон**: Поддерживать профессиональный, но прямой тон

## Особые соображения

- Кириллица с 33 буквами (включая ё, которая обязательна где необходимо)
- 6 падежей (именительный, родительный, дательный, винительный, творительный, предложный)
- 3 рода (мужской, женский, средний) с правильным согласованием
- Множественные числа имеют три формы: 1 (день), 2-4 (дня), 5+ (дней)
- Важное различие: "пароль" для учётных записей vs "кодовая фраза" для защиты отдельных секретов
- Секрет (мужской род), ссылка (женский род), шифрование (средний род)
- Использование правильных окончаний: создан (мужской), создана (женский), создано (средний)

## Обоснование ключевых терминологических решений

### «Секрет» vs «Тайна»

| Критерий | секрет | тайна |
|----------|--------|-------|
| Коннотация | Нейтральная, техническая | Личная, эмоциональная |
| Контекст использования | IT, безопасность, бизнес | Личные отношения, литература |
| Примеры в IT | «секретный ключ», «секрет API» | Не используется |
| Рекомендация | **Использовать** | Избегать |

**Вывод:** «Секрет» — стандартный термин в IT-контексте (ср. «секретный ключ», «API secret»), в то время как «тайна» несёт эмоциональную окраску и ассоциируется с личными секретами.

### «Уничтожить» vs «Сжечь» (burn)

| Критерий | уничтожить | сжечь |
|----------|------------|-------|
| Контекст | Цифровой, данные | Физический, огонь |
| Естественность | Звучит профессионально | Звучит буквально/странно |
| Устойчивые выражения | «уничтожить данные» | «сжечь документы» (бумажные) |
| Рекомендация | **Использовать** | Избегать |

**Вывод:** В цифровом контексте «уничтожить» — естественный выбор. Буквальный перевод «сжечь» создаёт когнитивный диссонанс.

### «Аккаунт» vs «Учётная запись»

| Критерий | аккаунт | учётная запись |
|----------|---------|----------------|
| Стиль | Современный, разговорный | Формальный, официальный |
| Длина | Короткий (7 символов) | Длинный (14 символов) |
| Целевая аудитория | Широкая, молодая | Корпоративная, старшая |
| Рекомендация | Допустим | Допустим |

**Вывод:** Оба варианта приемлемы. Важно выбрать один и использовать последовательно во всём приложении.

### «Кодовая фраза» vs «Фраза-пароль» (passphrase)

| Критерий | кодовая фраза | фраза-пароль |
|----------|---------------|--------------|
| Отличие от «пароля» | Чёткое | Менее чёткое |
| Профессиональность | Высокая | Средняя |
| Понятность | Интуитивная | Требует объяснения |
| Рекомендация | **Использовать** | Допустим |

**Вывод:** «Кодовая фраза» чётко отличается от обычного «пароля» и звучит профессионально.

---

## Russian Translation Notes

# Russian (ru) Translation Notes

## Audience

Russian is an official or widely-used language across multiple regions:

| Region | Russian Speakers | Notes |
|--------|-----------------|-------|
| Russia | ~145 million | Standard reference |
| Belarus | ~7 million | Official language alongside Belarusian |
| Kazakhstan | ~10 million | Official language |
| Kyrgyzstan | ~3 million | Official language |
| Baltic States | ~2 million | Significant minority |
| Diaspora (US, DE, IL) | ~5 million | Mixed usage patterns |

Our translations should be accessible to **all Russian speakers** regardless of location.

### Standard Written Russian

Use **standard written Russian** (литературный язык) as found in major Russian-language tech products with standard vocabulary, established IT terminology, and natural phrasing.

- Standard vocabulary recognized across all regions
- Established IT terminology
- Natural phrasing without regional colloquialisms

**What this means in practice:**
- IT terminology has no regional variants — "шифрование", "аутентификация", "сервер" are universal
- UI vocabulary is neutral — "Войти", "Настройки", "Отправить" work everywhere
- Avoid informal regional expressions in professional contexts

### Quality Benchmark

PR #2130 (December 2025), submitted by a contributor from Minsk, Belarus, demonstrates the expected quality standard: **neutral literary Russian** without regional markers, appropriate for a global audience. This serves as a reference for future contributions.

## Thinking Behind Translation Adjustments

The goal is to ensure accuracy, consistency, natural phrasing for Russian speakers, and adherence to the provided translation guidelines while properly handling Russian grammatical complexity.

### 1. Consistency of Core Terms

**Rationale:** Russian translations must maintain consistent terminology across the application, with special attention to grammatical agreement and proper technical vocabulary.

**Examples:**

- **`secret`**: Consistently translated as `секрет` (masculine gender) when referring to the confidential item being shared. This aligns with the guideline to emphasize the confidential *item*. The masculine gender requires proper agreement: `секрет создан` (the secret was created), `секрет удалён` (the secret was deleted).

- **`password`**: Consistently translated as `пароль` when referring to the *account login* credential. This is the standard term in Russian for account passwords. Used in contexts like account login and password reset.

- **`passphrase`**: Consistently translated as `кодовая фраза` when referring to the protection for an *individual secret*. This compound term clearly distinguishes it from the account `пароль` and follows the guideline to use a term implying a phrase-based security measure. Alternative considered: `парольная фраза`, but `кодовая фраза` sounds more professional.

- **`Dashboard`**: Translated as `Панель управления` (Control Panel) for better accuracy in professional software context, which is more descriptive than just `Панель`.

- **`Sign In`**: Translated as `Войти` (infinitive form used as imperative) - the standard, concise term for authentication in Russian interfaces.

- **`burn`**: Translated as `уничтожить` (to destroy) rather than literal `сжечь` (to burn). The literal translation would sound awkward in digital context. For status: `уничтожен`. Alternative: `удалить` (delete) is acceptable but less emphatic about permanence.

### Why "секрет" not "тайна"

The word "secret" in English maps to two Russian words with different connotations:

| Word | Connotation | IT Usage | Recommendation |
|------|-------------|----------|----------------|
| **секрет** | Technical, neutral | Common ("API secret", "секретный ключ") | **Use this** |
| **тайна** | Personal, emotional | Rare | Avoid |

Unlike the Danish case (where "Hemmeligheder" carries childish connotations requiring "Beskeder"), Russian **"секрет"** works perfectly in professional/security contexts. No exception needed.

### 2. Appropriate Voice (Imperative vs. Declarative/Passive)

**Rationale:** Guidelines specify imperative for user actions (buttons, links) and passive/declarative for informational text (status, descriptions, help).

**Examples:**

- **Button text**: Use infinitive forms that function as imperatives
  - `Создать секрет` (Create secret)
  - `Скопировать в буфер обмена` (Copy to clipboard)
  - `Подтвердить` (Confirm)

- **Status descriptions**: Use short-form past participles with proper gender agreement
  - `Скопировано в буфер обмена` (Copied to clipboard - neuter, passive)
  - `Секрет создан` (Secret created - masculine, passive)
  - `Ссылка создана` (Link created - feminine, passive)

- **Help text**: Use declarative sentences with polite вы form
  - `Вы просматриваете секретное содержимое` (You are viewing the secret content)
  - `Это содержимое отображается только один раз` (This content is shown only once)

### 3. Clarity and Natural Phrasing

**Rationale:** Some translations require adaptation to sound natural in Russian while maintaining clarity.

**Examples:**

- **`copied to clipboard`**: Translated as `Скопировано в буфер обмена` (standard Russian phrase, neuter gender agrees with implicit "содержимое"/content)

- **`FAQ`**: Translated as `Частые вопросы` or `Вопросы и ответы` (clearer than abbreviation, which doesn't work well in Russian)

- **`Loading...`**: Translated as `Загрузка...` (standard, using nominative case)

- **`Remember me`**: Translated as `Запомнить меня` (infinitive form, more natural than imperative `Запомни меня` which sounds too direct)

### 4. Formal Address (Вы)

**Rationale:** Russian requires choosing between informal "ты" and formal "вы". Professional software should consistently use the formal "вы" form with capital В when directly addressing the user.

**Examples:**

Most user-facing instructions use forms implying formal "вы":
- `Введите Ваш пароль` (Enter your password - formal)
- `Ваше секретное сообщение` (Your secret message - formal possessive)
- `Вы можете...` (You can... - formal, capitalized)

**When to capitalize Вы:**
- Always capitalize when directly addressing the user in singular formal context
- `Вы`, `Вас`, `Вам`, `Вами`, `Ваш`, `Ваша`, `Ваше`, `Ваши`

### 5. Gender Agreement

**Rationale:** Russian requires strict gender agreement between nouns, adjectives, and past participles.

**Critical genders to remember:**
- `секрет` (secret) - masculine → `создан`, `удалён`, `активный`
- `ссылка` (link) - feminine → `создана`, `удалена`, `активная`
- `сообщение` (message) - neuter → `создано`, `удалено`, `активное`
- `шифрование` (encryption) - neuter → `включено`, `выключено`

**Examples:**
- ✓ `Секрет был создан` (The secret was created - masculine)
- ✗ `Секрет была создана` (incorrect feminine agreement)
- ✓ `Ссылка была создана` (The link was created - feminine)
- ✓ `Сообщение было создано` (The message was created - neuter)

### 6. Plural Forms (Russian Three-Form System)

**Rationale:** Russian requires three distinct plural forms based on the last digit of the number.

**Rules:**
1. **Singular form**: numbers ending in 1 (except 11)
   - 1 день, 21 день, 101 день

2. **First plural form**: numbers ending in 2, 3, 4 (except 12, 13, 14)
   - 2 дня, 3 дня, 4 дня, 22 дня, 103 дня

3. **Second plural form**: numbers ending in 0, 5-9, 11-14
   - 5 дней, 10 дней, 11 дней, 25 дней, 100 дней

**Implementation examples:**
```
function getRussianPluralForm(count, forms) {
  const n = Math.abs(count) % 100;
  const n1 = n % 10;

  if (n > 10 && n < 20) return forms[2];  // 11-14 дней
  if (n1 > 1 && n1 < 5) return forms[1];  // 2-4 дня
  if (n1 === 1) return forms[0];          // 1 день
  return forms[2];                        // 5+ дней
}

// Usage:
getRussianPluralForm(1, ['день', 'дня', 'дней'])    // день
getRussianPluralForm(2, ['день', 'дня', 'дней'])    // дня
getRussianPluralForm(5, ['день', 'дня', 'дней'])    // дней
getRussianPluralForm(21, ['день', 'дня', 'дней'])   // день
```

### 7. Verb Aspects (Perfective vs. Imperfective)

**Rationale:** Russian verbs have two aspects that convey different meanings.

**Perfective aspect** (completed action, result-focused):
- `создать` (to create - once, completed)
- `скопировать` (to copy - once, completed)
- `отправить` (to send - once, completed)

**Imperfective aspect** (process, repeated, or ongoing action):
- `создавать` (to be creating, to create regularly)
- `копировать` (to be copying, to copy regularly)
- `отправлять` (to be sending, to send regularly)

**Usage in UI:**
- Buttons typically use perfective infinitives (single action expected):
  - `Создать` (Create)
  - `Скопировать` (Copy)
  - `Удалить` (Delete)

- Descriptions may use imperfective for ongoing states:
  - `Система шифрует данные` (The system encrypts data - ongoing)
  - `Пользователи создают секреты` (Users create secrets - repeated action)

### 8. Case System

**Rationale:** Russian has 6 grammatical cases that must be applied correctly.

**Common cases in UI:**

**Nominative (Именительный)** - subject of sentence:
- `секрет` (secret)
- `пароль` (password)

**Genitive (Родительный)** - possession, after negation, with numbers:
- `создание секрета` (creation of a secret)
- `нет пароля` (no password)
- `5 дней` (5 days)

**Dative (Дательный)** - indirect object, "to/for":
- `отправить пользователю` (send to user)

**Accusative (Винительный)** - direct object:
- `создать секрет` (create a secret)
- `введите пароль` (enter password)

**Instrumental (Творительный)** - "by means of", "with":
- `защищено паролем` (protected with password)
- `зашифровано ключом` (encrypted with key)

**Prepositional (Предложный)** - after certain prepositions:
- `в панели управления` (in the dashboard)
- `о конфиденциальности` (about privacy)

### 9. Essential Use of Ё

**Rationale:** The letter Ё must be used where needed, not substituted with Е.

**Critical examples:**
- `всё` (everything) vs. `все` (all/everyone)
- `ещё` (still, yet, more) vs. `еще` (archaic or wrong)
- `приём` (reception) vs. `прием` (wrong spelling)

**Impact on meaning:**
- `передает` (передаёт - passes, transmits)
- `узнает` (узнаёт - finds out)

### 10. Technical Terminology

**Rationale:** Use established Russian IT terminology.

**Standard technical terms:**
- шифрование (encryption) - not кодирование (encoding)
- аутентификация (authentication) - standard transliteration
- DNS-запись (DNS record) - hyphenated compound
- CNAME-запись (CNAME record) - hyphenated compound
- API (API) - unchanged, pronounced as individual letters
- токен (token) - transliterated, masculine gender

### 11. Completeness

**Rationale:** All user-facing text must be fully translated with proper Russian grammar.

**Areas requiring translation:**
- Button labels and calls to action
- Help text and tooltips
- Error messages and warnings
- Email templates
- Marketing copy
- System status messages
- Form labels and placeholders

## Summary of Changes for Russian Locale

- **Terminology**: Standardized key terms like `секрет`, `пароль`, `кодовая фраза`, `Панель управления`, `Войти`, `окончательное удаление` for consistency and guideline adherence

- **Voice**: Consistently applied imperative (infinitive) voice for actions and passive/declarative voice for informational text

- **Gender Agreement**: Ensured proper agreement between nouns, adjectives, and past participles
  - секрет (m) → создан, удалён
  - ссылка (f) → создана, удалена
  - сообщение (n) → создано, удалено

- **Plural Forms**: Implemented three-form plural system for all countable nouns
  - 1/21/101 день
  - 2-4/22-24 дня
  - 5-20/25-30 дней

- **Formal Address**: Consistent use of formal "вы" form with proper capitalization (Вы, Ваш)

- **Verb Aspects**: Proper use of perfective/imperfective aspects based on context
  - Perfective for buttons and completed actions
  - Imperfective for processes and repeated actions

- **Case Declension**: Correct application of all 6 Russian grammatical cases

- **Cyrillic Integrity**: Proper use of all Cyrillic letters including mandatory Ё

- **Technical Accuracy**: Use of established Russian IT terminology

- **Natural Phrasing**: Idiomatic Russian expressions that sound natural to native speakers

The translations aim for clarity and adherence to standard Russian usage in technical contexts, while respecting the specific grammatical requirements of the Russian language, including gender agreement, plural forms, verb aspects, and case declension.

## Common Pitfalls for Russian Translations

### 1. Key Naming (Technical)

**CRITICAL:** Never change JSON key names when translating. Only translate values.

```json
// WRONG - key was renamed
- "have-more-questions-visit-our": "Have more questions?"
+ "have_more_questions_visit_our": "Есть вопросы?"  // BREAKS APPLICATION!

// CORRECT - only value changed
  "have-more-questions-visit-our": "Есть ещё вопросы? Посетите наш"
```

### 2. Unicode Encoding

Ensure proper UTF-8 encoding. Watch for corruption:
- `Это��` should be `Этот`
- Check for mojibake (garbled characters)

### 3. Vue-i18n Pluralization

Russian requires 3 plural forms, but Vue-i18n pipe format varies by version:

```json
// Vue-i18n format (check project version)
"day": "день | дня | дней"

// Verify with test values:
// 1, 21, 31, 101 → день (singular)
// 2, 3, 4, 22, 23, 24 → дня (few)
// 5-20, 25-30, 100 → дней (many)
```

### 4. Informal Register Inconsistency

Maintain consistent formal "вы" register throughout:
- ✓ `Вы можете безопасно закрыть эту вкладку`
- ✓ `С возвращением` (appropriate for "Welcome Back")
- ✗ `Ну что ж, вперёд` (too informal for professional context)

### 5. Good Translation Examples (from PR #2130)

These translations demonstrate the expected quality:

| English | Russian | Why It Works |
|---------|---------|--------------|
| "What am I looking at?" | "Что я вижу?" | Natural simplification, not literal |
| "Copy to clipboard" | "Копировать в буфер обмена" | Standard UI term |
| "Account deleted successfully" | "Аккаунт успешно удалён" | Modern, natural |
| "Permanently delete account" | "Безвозвратно удалить аккаунт" | Conveys finality |
| "Welcome Back" | "С возвращением" | Idiomatic, warm but professional |
| "This action cannot be undone" | "Это действие нельзя отменить" | Clear, direct |

### 6. Character Expansion

Russian typically expands 10-25% from English. Check UI constraints:
- Button text: May need shorter alternatives
- Navigation labels: Test for wrapping
- Form labels: May need multi-line support

## Key Differences from Other Languages

**Compared to Spanish:**
- Russian requires gender agreement throughout (Spanish has only 2 genders, Russian has 3)
- Russian has 6 cases vs Spanish's simpler structure
- Russian requires 3 plural forms vs Spanish's 2
- Russian uses formal Вы (capitalized) vs Spanish tú/usted distinction
- Russian verb aspects (perfective/imperfective) have no Spanish equivalent

**Compared to English:**
- Russian requires explicit gender marking
- Russian has complex case system
- Russian has three-form plural system
- Russian requires aspect selection for verbs
- Russian has flexible word order (but standard for UI)
- Russian requires formal address form

**Unique Russian considerations:**
- Mandatory use of letter Ё for clarity
- Compound technical terms often hyphenated (DNS-запись)
- Transliterated English terms maintain original stress and pronunciation patterns
- Some English borrowings are preferred in tech contexts (e.g., "email" often used alongside "электронная почта")

---

## Document Information

This guide was generated from the following source files:

- Universal resources: `/en/translations/universal/`
- Glossary: `/ru/translations/glossary.md`
- Language notes: `/ru/translations/language-notes.md`

Generated: 2026-01-20
