# Translation Guidance for Japanese (日本語)

This document combines the Onetime Secret translation glossary and language-specific translation notes for Japanese. It serves as a comprehensive reference for translators and the saas-translator skill to ensure consistency, accuracy, and cultural appropriateness in Japanese translations.

## Overview

This guide covers:
- Standard terminology translations for core concepts
- User interface elements and their Japanese equivalents
- Language-specific considerations and rationale for translation choices
- Voice, tone, and cultural adaptation guidelines
- Translation principles and best practices

---

## Core Terminology

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| secret (noun) | シークレット | アプリケーションの中心概念（製品機能を指す場合） |
| secret (adj) | 機密の、秘密の | 形容詞として使用する場合 |
| passphrase | パスフレーズ | シークレット保護のための認証方法 |
| burn | 削除 | 閲覧前にシークレットを破棄するアクション |
| view/reveal | 表示/閲覧 | シークレットにアクセスするアクション |
| link | リンク | シークレットへのアクセスを提供するURL |
| encrypt/encrypted | 暗号化/暗号化された | セキュリティ方式 |
| secure | 安全な、セキュアな | 保護状態 |

### Key Term Explanations

#### "Secret" Translation
- **Choice:** "シークレット" (shīkuretto) - カタカナ形式
- **Rationale:** Creates a clear technical term for shared confidential information in the context of the product
- **Avoided:** "秘密" (himitsu) which has connotations of "personal secrets" and is too general
- **Usage Examples:**
  - 製品機能として: 「シークレットを作成」「シークレットリンク」
  - 一般的な形容詞として: 「機密情報」「秘密のメッセージ」

#### "Burn" Translation
- **Choice:** "削除" (sakujo) - "delete/remove"
- **Rationale:** Better communicates permanent deletion concept than literal "burn" (燃やす/moyasu) in Japanese context
- **Usage Examples:** 「シークレットを削除」「削除済み」
- **Translation Example:**
  ```
  "burn_this_secret": "このシークレットを削除"
  ```

#### Passphrase vs Password Distinction
- **Password (パスワード):** アカウントログイン用の認証情報
  - 使用例: 「アカウントパスワード」「ログインパスワード」
- **Passphrase (パスフレーズ):** 個別のシークレット保護用
  - 使用例: 「パスフレーズで保護」「パスフレーズ必須」
- **Rationale:** Critical distinction for user understanding of security mechanisms
- **Important:** この区別を常に維持すること

---

## User Interface Elements

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| Share a secret | シークレットを共有 | メインアクション |
| Create Account | アカウントを作成 | 登録 |
| Sign In | ログイン/サインイン | 認証 |
| Dashboard | ダッシュボード/アカウント | ユーザーのメインページ |
| Settings | 設定 | 設定ページ |
| Privacy Options | プライバシーオプション | シークレット設定 |
| Feedback | フィードバック/ご意見 | ユーザーコメント |

---

## Status Terms

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| received | 受信済み/閲覧済み | シークレットが閲覧された |
| burned | 削除済み | シークレットが閲覧前に削除された |
| expired | 期限切れ | 時間経過によりシークレットが利用不可 |
| created | 作成済み | シークレットが生成された |
| active | 有効/アクティブ | シークレットが利用可能 |
| inactive | 無効/非アクティブ | シークレットが利用不可 |

---

## Time-Related Terms

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| expires in | 有効期限 | シークレットが利用できなくなるまでの時間 |
| day/days | 日 | 時間単位 |
| hour/hours | 時間 | 時間単位 |
| minute/minutes | 分 | 時間単位 |
| second/seconds | 秒 | 時間単位 |

---

## Security Features

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| one-time access | 1回限りのアクセス | コアセキュリティ機能 |
| passphrase protection | パスフレーズ保護 | 追加セキュリティ |
| encrypted in transit | 転送中の暗号化 | データ保護方法 |
| encrypted at rest | 保存時の暗号化 | ストレージ保護 |

### Important Security Translation Examples

```
"careful_only_see_once": "注意: これは一度しか表示されません。"
```
Added Japanese warning marker "注意:" to emphasize importance in culturally appropriate way

```
"view_secret": "シークレットを表示"
```
Consistently used "シークレット" rather than mixing with "秘密"

```
"security-policy": "セキュリティポリシー"
```
Completed previously truncated security section with proper translations

---

## Account-Related Terms

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| email | メール/Eメール | ユーザー識別子 |
| password | パスワード | アカウント認証 |
| account | アカウント | ユーザープロフィール |
| subscription | サブスクリプション/定期購入 | 有料サービス |
| customer | お客様/顧客 | 有料ユーザー |

---

## Domain-Related Terms

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| custom domain | カスタムドメイン | プレミアム機能 |
| domain verification | ドメイン検証 | セットアッププロセス |
| DNS record | DNSレコード | 設定 |
| CNAME record | CNAMEレコード | DNS設定 |

---

## Error Messages

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| error | エラー | 問題通知 |
| warning | 警告 | 注意通知 |
| oops | おっと | フレンドリーなエラー表示 |

---

## Buttons and Actions

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| submit | 送信 | フォームアクション |
| cancel | キャンセル/取り消し | 否定的なアクション |
| confirm | 確認 | 肯定的なアクション |
| copy to clipboard | クリップボードにコピー | ユーティリティアクション |
| continue | 続ける | ナビゲーション |
| back | 戻る | ナビゲーション |

---

## Marketing Terms

| 英語 | 日本語 (ja) | 文脈 |
|---------|-------------|-------|
| secure links | セキュアリンク/安全なリンク | 製品機能 |
| privacy-first design | プライバシー第一の設計 | デザイン哲学 |
| custom branding | カスタムブランディング | プレミアム機能 |

---

## Voice and Tone Guidelines

### 敬語とトーン

- **基本方針**: です/ます調を使用
- **ボタン/アクション**: 命令形（「保存」「削除」「送信」）
- **ステータス**: 受動態または過去形（「保存されました」「削除済み」）
- **説明文**: 丁寧語を使用し、プロフェッショナルかつ親しみやすいトーンを維持

### Voice Application by Context

1. **Action Buttons and Controls**
   - Use imperative form (命令形)
   - Examples: 「送信」「保存」「削除」「コピー」

2. **Status Messages and Notifications**
   - Use passive/declarative form (受動態/完了形)
   - Examples: 「保存されました」「削除済み」「送信完了」

3. **Explanatory Text**
   - Use polite form (丁寧語)
   - Maintain professional yet approachable tone
   - Use proper particles and sentence endings (です/ます)

### Cultural Adaptation Examples

```
"secret_was_truncated": "メッセージが切り詰められました"
```
Used "message was truncated" rather than "secret was truncated" for natural Japanese expression

```
"careful_only_see_once": "注意: これは一度しか表示されません。"
```
Added Japanese warning marker "注意:" to emphasize importance

---

## Technical Terms Handling

### 技術用語の扱い

- セキュリティ関連の技術用語は、正確さを優先
- 一般的に使用されているカタカナ表記を採用
- **そのまま使用する用語**: API、DNS、SSL/TLS、URL
- **例外**: より自然な日本語訳がある場合はそちらを優先

### Technical Accuracy Examples

- Maintained all placeholders ({0}, {count}, etc.) for dynamic content
- Preserved formatting and special characters
- Ensured security concepts were accurately conveyed

---

## Translation Principles

### Core Guidelines

1. **一貫性 (Consistency)**: アプリケーション全体を通して同じ訳語を使用すること
2. **文脈 (Context)**: その用語がアプリケーションでどのように使用されているかを考慮する
3. **文化的適応 (Cultural Adaptation)**: 必要であれば、用語を日本の慣習に合わせる
4. **技術的正確さ (Technical Accuracy)**: セキュリティ用語が正確に翻訳されていることを確認する
5. **口調 (Tone)**: プロフェッショナルでありながら親しみやすい口調を維持する

### Detailed Principles

1. **Consistency with existing terminology** - Matched terms already translated elsewhere
2. **Natural language flow** - Prioritized natural-sounding Japanese over literal translations
3. **Voice and tone adaptation** - Used appropriate active/imperative voice for UI actions and passive/declarative voice for status messages
4. **Technical precision** - Maintained accurate translations for security terms
5. **Cultural appropriateness** - Adapted expressions to fit Japanese communication norms

---

## Translation Best Practices

### Structural Considerations

- Fixed JSON structure issues
- Completed previously incomplete translations
- Ensured consistency across all sections

### Clarity Enhancements

- Replaced literal translations with functionally equivalent Japanese terms
- Prioritized user understanding over word-for-word translation
- Used proper honorifics and politeness levels

### Quality Assurance

- Established consistent translations for key terms (secret, password, passphrase)
- Created clear distinctions between technical concepts
- Aligned technical terms with existing translations
- Adjusted phrasing to sound more natural in Japanese
- Used Japanese-style warnings and notifications where appropriate

---

## Summary of Key Changes and Improvements

### Terminology Standardization
- Established consistent translations for key terms
- Created clear distinctions between technical concepts (password vs passphrase)
- Aligned technical terms with existing translations

### Cultural Adaptation
- Adjusted phrasing to sound more natural in Japanese
- Used Japanese-style warnings and notifications where appropriate
- Applied imperative form for action buttons
- Used passive form for status messages

### Technical Accuracy
- Ensured security concepts were accurately conveyed
- Maintained all placeholders for dynamic content
- Preserved formatting and special characters

---

**Note**: This guide should be referenced for all Japanese translation work to maintain consistency and quality across the Onetime Secret application.
