# Requirements: WhisperClip v1.1 Speaker Diarization

**Defined:** 2026-03-22
**Core Value:** Точна транскрипція зустрічей з правильною атрибуцією спікерів.

## v1.1 Requirements

### Pipeline (PIPE)

- [x] **PIPE-01**: System накопичує аудіо в per-speaker буфер безперервно замість fixed 5s chunks
- [x] **PIPE-02**: Коли diarizer фіксує зміну спікера — поточний буфер закривається і Whisper запускається на накопиченому аудіо
- [x] **PIPE-03**: Якщо один спікер говорить >30с без зміни — буфер примусово закривається (max duration cap) і відкривається новий
- [x] **PIPE-04**: Кожен закритий буфер відправляється в Whisper як атомарна задача — текст 100% атрибутований одному спікеру
- [x] **PIPE-05**: Мікрофонне аудіо обробляється окремо від системного — завжди "Me", diarization не застосовується
- [x] **PIPE-06**: Буфери коротші 0.5с (8,000 samples) відхиляються без запуску Whisper — запобігає garbled short utterances

### Speaker ID (SPKR)

- [x] **SPKR-01**: Системне аудіо обробляється через DiarizerManager зі стабільними speaker IDs впродовж усієї сесії запису
- [x] **SPKR-02**: clusteringThreshold встановлено на 0.3 (speakerThreshold=0.36) для надійного розрізнення різних голосів у streaming режимі
- [x] **SPKR-03**: Спікерам призначаються стабільні мітки "Speaker 1", "Speaker 2" що зберігаються між усіма буферами сесії

### Real-time UI (RT)

- [x] **RT-01**: Waveform у recording bar змінює колір залежно від поточного активного спікера в реальному часі
- [x] **RT-02**: Кожен спікер має власний унікальний колір з palette, що відповідає кольорам у chat view
- [x] **RT-03**: Перехід кольору waveform відбувається в момент детекції зміни спікера (не з затримкою чанку)

### Chat UI (CHAT)

- [ ] **CHAT-01**: Consecutive segments одного спікера в живому транскрипті (MeetingNotesView) і в збереженій зустрічі (MeetingDetailView) відображаються як один chat-style bubble на репліку (рішення власника 2026-10-15)
- [ ] **CHAT-02**: Ім'я спікера та аватар показуються один раз зверху кожної групи (не повторюється на кожному сегменті)
- [ ] **CHAT-03**: Timestamp показується тільки в кінці кожної групи, не на кожному бублі
- [ ] **CHAT-04**: "Me" сегменти вирівняні вправо, сегменти інших спікерів — вліво (iMessage style)

## v1.2 Requirements — додано 2026-10-13 (перенесення напрацювань з `../stt-diarization`)

### Залежності (DEP)

- [x] **DEP-01**: Зафіксовано базовий стан: результат локальної збірки і тестів на гілці до будь-яких оновлень залежностей
- [x] **DEP-02**: LLM-стек переведено на `mlx-swift-lm` 3.32.x + `mlx-swift` 0.32.x; проєкт збирається локально, тести проходять (CI — поза скоупом)
- [x] **DEP-03**: FluidAudio оновлено до 0.17.x без регресій у Parakeet-стрімінгу та транскрипції файлів

- [x] **DEP-04**: WhisperKit оновлено до 1.1.x (Argmax OSS SDK) без регресій у диктуванні, транскрипції файлів і стрімінгу; вже завантажені моделі не перезавантажуються

### Gemma 4 (GEMMA)

- [x] **GEMMA-01**: Gemma 4 E4B (`mlx-community/gemma-4-e4b-it-4bit`) доступна у списку локальних LLM, завантажується і генерує
- [x] **GEMMA-02**: Усі наявні LLM зі списку продовжують працювати після міграції

### Nemotron 3 Diarization (NEMO)

- [x] **NEMO-01**: Системне аудіо діаризується через `Nemotron3Diarizer` (CoreML) у стрімінговому режимі
- [x] **NEMO-02**: Мітки спікерів стабільні протягом усієї сесії для 3+ спікерів (до 8)
- [x] **NEMO-03**: Пресет латентності налаштовується; за замовчуванням `fast32` (2,88 с)
- [x] **NEMO-04**: Старий шлях `DiarizerManager` (кластеризація) видалено; без завантаженої моделі застосунок працює з атрибуцією за джерелом (мікрофон → «Me», системне аудіо → один нерозділений співрозмовник) і показує, що розділення спікерів вимкнено

### Reconciler (REC) — додано 2026-10-14

- [x] **REC-01**: Системне аудіо з'являється текстом одразу під «Pending»; мітка «Speaker N» приходить протягом ~2 вікон діаризатора (~6 с на `fast32`)
- [x] **REC-02**: Рядок, що перетинає зміну мовця, ділиться на межі (по словах для Parakeet; для WhisperKit — без поділу, мітка за більшістю); слова не губляться і не дублюються
- [x] **REC-03**: Reconciler — окремий актор, що тестується без аудіо і моделей; живий список і збережена зустріч не містять застарілих рядків чи дублікатів

### Hugging Face токен (TOKEN) — відкладено 2026-10-13

Репозиторій `FluidInference/nemotron-3-diarization-coreml` виявився публічним (перевірено 2026-10-13), тож токен для фази 11.4 не потрібен. Вимоги лишаються як заготовка на випадок закритої моделі; див. `IDEAS.md`.

- [ ] **TOKEN-01**: Користувач вводить HF-токен у Settings (і в Onboarding при завантаженні моделі)
- [ ] **TOKEN-02**: Токен зберігається в Keychain, ніколи не логується і не потрапляє в `UserDefaults`
- [ ] **TOKEN-03**: UI розрізняє помилки «невалідний токен» і «немає доступу до gated-репозиторію» та веде на сторінку запиту доступу

### Голосові профілі (VOICE)

- [ ] **VOICE-01**: Перейменування спікера застосовується до всіх його сегментів у зустрічі
- [ ] **VOICE-02**: Для названого спікера зберігається голосовий профіль (кілька зразків на людину)
- [ ] **VOICE-03**: У наступних зустрічах відомий спікер підписується іменем автоматично
- [ ] **VOICE-04**: Профілі можна переглянути, об'єднати і видалити; дані не залишають пристрій

## v2 Requirements

### Speaker Naming

- **NAME-01**: Користувач може перейменувати "Speaker 1" → власне ім'я (Олексій) у MeetingDetailView
- **NAME-02**: Перейменування застосовується до всіх сегментів спікера в поточній зустрічі
- **NAME-03**: Імена зберігаються і пропонуються для нових зустрічей (speaker fingerprint)

### Quality

- **QUAL-01**: Min segment duration перед відправкою в Whisper (< 0.5s → пропустити)
- **QUAL-02**: Confidence score per segment відображається в UI (опціонально)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Speaker naming / fingerprinting | v1.2 — потребує окремої UX роботи |
| Cloud sync або export | Local-first product |
| XCUITest / UI automation | Немає інфраструктури |
| SettingsView подальший рефакторинг | v1.0 завершено |
| Multi-language per-segment detection | Whisper вже обробляє, не потребує окремого requirements |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PIPE-01 | Phase 6 | Complete |
| PIPE-02 | Phase 6 | Complete |
| PIPE-03 | Phase 6 | Complete |
| PIPE-04 | Phase 6 | Complete |
| PIPE-06 | Phase 6 | Complete |
| SPKR-01 | Phase 6 | Complete |
| SPKR-02 | Phase 6 | Complete |
| SPKR-03 | Phase 6 | Complete |
| PIPE-05 | Phase 7 | Complete |
| RT-01 | Phase 9 | Complete |
| RT-02 | Phase 9 | Complete |
| RT-03 | Phase 9 | Complete |
| CHAT-01 | Phase 12 | Planned |
| CHAT-02 | Phase 12 | Planned |
| CHAT-03 | Phase 12 | Planned |
| CHAT-04 | Phase 12 | Planned |

| DEP-01 | Phase 11.3 | Complete (гілка не збирається: FluidAudio 0.10.0 vs Swift 6.3.3) |
| DEP-02, DEP-03, DEP-04 | Phase 11.3 | Complete (UAT 2026-10-13) |
| GEMMA-01 | Phase 11.3 | Complete (UAT 2026-10-13) |
| GEMMA-02 | Phase 11.3 | Complete by owner decision 2026-10-13 — existing LLMs not run by hand, see `11.3-UAT.md` "Residual risk" |
| NEMO-01..04 | Phase 11.4 | Complete (UAT 2026-10-14) |
| REC-01..03 | Phase 13 | Complete 2026-10-15 (UAT 8/9 PASS, step 9 skipped by owner) |
| TOKEN-01..03 | — | Deferred (модель публічна; див. `IDEAS.md`) |
| VOICE-01..04 | Phase 14 | Pending |

**Coverage:**
- v1.1 requirements: 16 total
- Mapped to phases: 16
- Phase 8 (MeetingRecorder Rewire): integration phase, no new requirements — exercises all Phase 6+7 requirements end-to-end
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-22*
*Last updated: 2026-03-22 — traceability updated to match 5-phase roadmap (Phases 6-10)*
