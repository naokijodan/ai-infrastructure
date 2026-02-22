# AI活用 5階層インフラ構築ロードマップ

> 追加費用ゼロ / Mac1台完結 / Claude Codeサブスク範囲内
>
> 3者協議（Claude + GPT-5 + Gemini）の合意に基づく設計

---

## 現状

| 項目 | 状態 |
|------|------|
| Claude Code CLI | v2.1.45 ✅ |
| Docker | v29.2.0 ✅（rakuda用コンテナ稼働中） |
| Skills | 7つ構成済（resale-research, pdf, xlsx等） |
| MCP | 10+サーバー構成済（Figma, Obsidian, Playwright等） |
| 現在の階層 | 3F（部分的） |

---

## 3者協議の合意事項

| ポイント | 合意内容 |
|---------|---------|
| セキュリティ | Webhook HMAC署名必須、Cloudflare WAF/Rate Limit導入 |
| n8n実行方式 | **ホスト実行（npm install -g n8n）**を採用。Docker内からホストCLI呼び出しは複雑でリスク |
| スマホ入口 | iOSショートカット + LINE Bot。直行ルート（→n8n）のみ。経路複雑化禁止 |
| Phase順序 | Phase 1最優先。n8n PoCのみ並行可。本番は3F完成後 |
| 運用 | 実行回数ガード（日10回）、失敗通知必須、再起動後自動復旧設計 |
| 重要タスク | 承認フロー（通知→確認→実行）を挟む |

---

## Phase 1: 3F完成 — Skills/自動化基盤の整備

**目的**: Claude Codeを「手動で起動して対話する」から「コマンド1つで仕事が完了する」へ

### 1.1 ヘッドレス実行基盤

Claude Code はヘッドレスモード（`claude -p "プロンプト"`）で非対話実行できる。
これがn8n連携の前提になる。

**成果物**:
```
~/ai-scripts/
├── run-claude.sh          # 汎用ラッパー（ログ出力、エラーハンドリング、実行回数カウント）
├── templates/
│   ├── resale-research.md  # 転売リサーチ用プロンプト
│   ├── market-check.md     # 市場データチェック用
│   ├── ai-discussion.md    # 3者協議用
│   └── watch-data-add.md   # 時計データ追加用
├── logs/                   # 実行ログ
└── counter.txt             # 日次実行回数カウンター
```

### 1.2 既存プロトコルのSkills化

CLAUDE.mdに埋め込んでいるプロトコルを、独立したSkillsとして整理する。

| プロトコル | 現状 | 整理先 |
|-----------|------|--------|
| 転売リサーチ | skills/resale-research/ ✅ | そのまま |
| 3者協議 | CLAUDE.mdに記述 | skills/ai-discussion/SKILL.md |
| 時計データ追加 | CLAUDE.mdに記述 | skills/watch-data/SKILL.md |
| GitHub Pages公開 | CLAUDE.mdに記述 | skills/github-pages/SKILL.md |
| 開発ログ作成 | CLAUDE.mdに記述 | skills/dev-log/SKILL.md |

### 1.3 launchdで定期実行

Macのlaunchd（cron相当）で定期タスクを設定する。

**初期タスク候補**:
- 毎朝9時: eBay出品状況チェック → 変動があれば通知
- 毎日12時: 監視商品の価格チェック
- 毎週月曜: 週次レポート生成

**成果物**:
- launchd plistファイル（`~/Library/LaunchAgents/`）
- 各タスクのシェルスクリプト
- macOS通知による結果通知

---

## Phase 2: 4F構築 — n8nゲートウェイ

**目的**: 「トリガー → 自動でClaude Codeが動く」仕組みを作る

### 2.1 n8nホスト構築（3者協議で変更: Docker → ホスト実行）

```bash
npm install -g n8n
n8n start  # localhost:5678
```

**理由**: ホスト実行ならClaude Code CLIを直接呼べる。Docker経由は複雑でトラブル源。

**自動起動**: launchdでn8nをログイン時に自動起動する設定を追加。

### 2.2 n8n → Claude Code パイプライン

**基本フロー**:
```
[トリガー] → [認証チェック] → [実行回数チェック] → [run-claude.sh] → [後処理] → [通知]
```

**セキュリティ（3者協議合意）**:
- Webhook URLランダム化
- HMAC署名によるリクエスト検証
- Cloudflare WAF/Rate Limit
- 重要タスクは承認フロー付き

### 2.3 トリガー型タスク実装

**第1弾: ファイル監視トリガー**
- `~/Desktop/時計データ_分類済み.csv` の更新検知 → 自動でタブ再生成 & push

**第2弾: Webhook トリガー**
- 外部からHTTP POSTで任意のタスクを起動可能に
- HMAC署名検証必須

**第3弾: 条件付きトリガー**
- 定期的にデータチェック → 条件に合致した場合のみClaude Codeを起動

---

## Phase 3: 4F完成 — スマホ入口の構築

**目的**: スマホから一言送るだけでn8nのワークフローが起動する

### 3.1 iOS ショートカット連携（最優先）

- n8nのWebhookエンドポイントを作成
- iOSショートカットから「URLの内容を取得」でPOST
- 定型タスク用ショートカット:
  - 「市場チェック」ワンタップ
  - 「リサーチ開始」→ テキスト入力 → 実行
  - 「今日のサマリー」ワンタップ

**外部アクセス**:
- 同じWi-Fi内: ローカルIP:5678
- 外出先: Cloudflare Tunnel（無料）or Tailscale（無料）

### 3.2 LINE Bot

- LINE Developers でMessaging APIチャネル作成（無料枠200通/月）
- Webhook URL → n8nエンドポイント
- メッセージ解析 → Claude Codeタスクにルーティング
- 直行ルート: LINE → n8n → Claude Code（経路複雑化禁止）

---

## Phase 4: 5F到達 — 全自動統合

**目的**: 「スマホから一言」→「AI処理」→「結果通知」が完全自動で回る

### 4.1 既存プロトコルのフル統合

| プロトコル | スマホから | 自動実行 | 結果通知 |
|-----------|----------|---------|---------|
| 転売リサーチ | 「○○リサーチ」と送信 | Claude Code実行 | Excel + LINE通知 |
| 3者協議 | 「○○について協議」と送信 | multi_discuss実行 | 結果サマリーをLINE |
| 時計データ追加 | CSVをアップロード | 全自動パイプライン | 完了通知 |
| 市場チェック | ワンタップ | 定期 + オンデマンド | 変動があればLINE |
| 開発タスク | 「○○を修正して」と送信 | Claude Code実行 | commit/push + 通知 |

### 4.2 通知フロー整備

- LINE Bot: 処理結果をそのままLINEに返信
- macOS通知 → iPhone通知ミラーリング（バックアップ）

### 4.3 エラーハンドリング・監視（3者協議必須事項）

- タスク失敗時の即時LINE通知（サイレント失敗禁止）
- n8n実行履歴の定期チェック
- Claude Code実行のタイムアウト管理（5分上限）
- 再起動後の自動復旧（launchd RunAtLoad設定）

---

## 技術スタック（すべて無料）

| コンポーネント | 技術 | 費用 |
|--------------|------|------|
| AI処理 | Claude Code CLI（サブスク内） | ¥0 |
| ワークフロー | n8n ホスト実行（npm） | ¥0 |
| 定期実行 | macOS launchd | ¥0 |
| スマホ入口 | iOS ショートカット | ¥0 |
| チャット入口 | LINE Messaging API（無料枠） | ¥0 |
| 外部アクセス | Cloudflare Tunnel or Tailscale | ¥0 |
| 通知 | LINE返信 / macOS通知 | ¥0 |

---

## リスクと対策

| リスク | 対策 |
|--------|------|
| Macがスリープして止まる | Energy Saver設定 + caffeinate |
| Claude Codeサブスク上限 | 実行回数カウンター（日10回ガード） |
| Webhook不正アクセス | HMAC署名 + Cloudflare WAF/Rate Limit |
| n8nがクラッシュ | launchd KeepAlive設定で自動復旧 |
| 外出先からアクセス不可 | Cloudflare Tunnel（無料） |
| タスクのサイレント失敗 | 失敗時LINE即時通知 |
| Mac再起動後の復旧 | launchd RunAtLoad + 依存関係考慮した起動順序 |
