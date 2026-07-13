-- Exported from session_log table
-- 3 rows
-- Generated: 2026-07-13T10:05:43.037230

DELETE FROM session_log;

INSERT INTO session_log (id, date, locale, started_at, ended_at, task_count, notes, created_at) VALUES (1, '2026-01-21', 'multi', '2026-01-21T19:45:00', '2026-01-22 04:53:04', 32, 'QC review session across 12 locales (de, fr_FR, es, ja, zh, pt_BR, ru, ar, ko, nl, pl, tr).

Spawned parallel QC agents to spot-check translations. Identified 32 issues across severity levels:
- 4 critical (tr encoding errors, ja broadcast key)
- 7 high (ar RTL, ru formality, pt_BR passphrase term)
- 17 medium (terminology consistency, grammar, pluralization)
- 4 low (minor improvements)

Fixed 29 issues. Marked 3 as wontfix (framework-level pluralization for ar/ja, acceptable ko keyword variation).

Key fixes:
- tr: Fixed garbled text "ifꀕfa" → "ifşa", typos, passphrase terminology
- ja: Removed incorrect broadcast key path translation
- ar: Fixed RTL arrow direction
- ru: Standardized formality to formal Вы/Ваш, added 3rd plural form
- pt_BR: Fixed "senha mestre" → "frase secreta", "fachada" → "imagem"
- fr_FR: Fixed grammar "est devenu orphelin", standardized "secrets"
- nl: Standardized informal "je", burn term "vernietigingsfunctie"
- pl: Added 3rd plural forms for count strings
- zh: Standardized "机密信息", fixed tone "不可妥协"
- de: Standardized terminology in keywords

Added translation_issues table to schema for tracking QC findings.
Added QC protocol section to TRANSLATION_PROTOCOL.md.', '2026-01-22 04:53:04');
INSERT INTO session_log (id, date, locale, started_at, ended_at, task_count, notes, created_at) VALUES (2, '2026-07-02', 'multi', '2026-07-01T00:00:00', '2026-07-02T00:52:31', 0, '29-locale batch drain → per-locale i18n/update-<locale> branches → PRs #3574–3602 (all merged 2026-07-02).
Locales: ar,bg,ca_ES,cs,da_DK,de,de_AT,el_GR,eo,es,fr_CA,fr_FR,he,hu,it_IT,ja,ko,mi_NZ,nl,pl,pt_BR,pt_PT,ru,sl_SI,sv_SE,tr,uk,vi,zh.
BATCH_OPERATIONS.md was authored from this round. Per-round task count not captured (pre-dates session logging).', '2026-07-13 17:05:26');
INSERT INTO session_log (id, date, locale, started_at, ended_at, task_count, notes, created_at) VALUES (3, '2026-07-13', 'multi', '2026-07-13T10:05:42.947549', '2026-07-13T10:05:42.947549', 6090, '29-locale parallel drain, 6090/6090 tasks (210/locale), tidal-owl DB.
5-concurrent, one-writer-per-locale. Per-locale audits clean.
4 restart recoveries (bg, nl, el_GR, cs); ~15% agents stalled/died → verified DB pending + small-batch restart.
516 glossary rows inserted (Fable review). Locales mirror the 2026-07-02 set. Export/PR pending at time of logging.', '2026-07-13 17:05:42');
