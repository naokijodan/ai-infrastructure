# ai-infrastructure プロジェクトルール

## 役割分担【最重要】

| 役割 | 担当 | やること |
|------|------|----------|
| オーケストレーター | Claude Code | 設計・計画・タスク管理・ファイル構成決定・コマンド実行・Git操作・動作確認 |
| コーディング | OpenAI Codex CLI (`codex`) | シェルスクリプト・設定ファイル・コードの実装 |

### Claude Codeがやること
- 要件整理・設計判断
- Codex CLIへの指示（プロンプト作成・実行）
- 生成されたコードのレビュー・修正指示
- ファイル配置・Git操作・デプロイ
- n8n/launchd等の設定・起動・テスト
- 全体の進捗管理

### Claude Codeがやらないこと
- 自分で直接コードを書く（Codex CLIに委任する）

### 例外（Claude Codeが直接書いてよい場合）
- 1-2行の軽微な修正（typo、パス修正等）
- CLAUDE.md・README等のドキュメント
- Gitコミットメッセージ
- Codex CLIが使えない・応答しない場合のフォールバック

## Codex CLI 呼び出し方法

```bash
# 基本形
codex -q "指示内容"

# ファイル指定
codex -q "指示内容" --file path/to/file

# 作業ディレクトリ指定
cd ~/Desktop/ai-infrastructure && codex -q "指示内容"
```

## 3者協議の合意事項（必ず守る）

- n8nはホスト実行（Docker不可）
- WebhookにはHMAC署名必須
- スマホ入口は直行ルートのみ（経路複雑化禁止）
- 実行回数ガード: 日10回
- 失敗時は即時通知（サイレント失敗禁止）
- 重要タスクは承認フロー付き

## ファイル構成

| パス | 内容 |
|------|------|
| `~/Desktop/ai-infrastructure/` | プロジェクト本体 |
| `~/ai-scripts/` | ヘッドレス実行スクリプト・テンプレート |
| `~/Library/LaunchAgents/com.ai.*` | launchd定期実行 |
| `~/Library/LaunchAgents/com.n8n.*` | n8n自動起動 |
| `~/.claude/skills/` | Skills定義 |
