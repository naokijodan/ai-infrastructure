# LINE Bot 設定ガイド

以下は、n8n ワークフロー `n8n-workflows/line-bot-webhook.json` を使って LINE Bot を動かすための手順です。

## 1. LINE Developers へログイン
- https://developers.line.biz にアクセスし、LINE アカウントでログインします。

## 2. プロバイダー作成
- 「コンソール」→「新規プロバイダー作成」から任意のプロバイダー名で作成します。

## 3. Messaging API チャネル作成
- 作成したプロバイダーの配下で「新規チャネル作成」→「Messaging API」を選びます。
- 必要事項（アプリ名、メール、業種等）を入力し、利用規約に同意して作成します。

## 4. チャネルアクセストークン（長期）の取得
- チャネル設定画面の「Messaging API 設定」→「チャネルアクセストークン（ロングターム）」を発行し、値を控えます。
  - この値を n8n の環境変数 `LINE_CHANNEL_ACCESS_TOKEN` に設定します（後述）。

## 5. Webhook URL の設定
- Webhook URL に以下を設定します。
  - `https://ai-infra.{domain}/webhook/{workflow-id}/webhook/line-bot`
- `{domain}` はご自身のドメイン、`{workflow-id}` は n8n ワークフローの ID に置き換えてください。
  - 本リポジトリのワークフローでは Webhook ノードのパスは `line-bot` です。
  - n8n がリバースプロキシ配下の場合、ベース URL 設定に合わせて適宜調整してください。

## 6. Webhook 利用の有効化
- チャネル設定の「Webhook」→「利用する」をオンにします。

## 7. 応答メッセージの無効化
- 「応答メッセージ」→「利用しない」に設定します（Bot 側で返信するため）。

## 8. n8n 環境変数の設定
- n8n が動作する環境に `LINE_CHANNEL_ACCESS_TOKEN` を設定します。
  - Docker（例）: `-e LINE_CHANNEL_ACCESS_TOKEN="<発行したロングタームトークン>"`
  - ホスト環境（例）: `.env` やプロセスマネージャにて同様に設定
- n8n を再起動して反映します。

## 9. テスト方法
- LINE アプリで該当チャネルの Bot を友だち追加します。
- 任意のメッセージを送信します。
  - キーワードとテンプレートの対応:
    - 「市場チェック」または `market` → `market-check`
    - 「リサーチ」または `research` → `resale-research`
    - 「議論」または `discuss` → `ai-discussion`
    - 「時計」または `watch` → `watch-data-add`
  - 上記以外の文は、そのままプロンプトとして処理されます。
- 正常に動作すると、Bot からテキストで返信が返ります。

## 10. トラブルシューティング
- 403/401 が返る: `LINE_CHANNEL_ACCESS_TOKEN` が誤っている可能性。権限や値を再確認してください。
- 200 が返らない: n8n の Webhook に到達していない可能性。公開 URL、リバースプロキシ、SSL 設定、ファイアウォールを確認。
- 返信が空/エラー: `run-claude.sh` のパスや実行権限を確認（ワークフローは `./run-claude.sh` を実行）。
- 長文が途中で切れる: LINE の文字数上限対策で一部切り詰めています。テンプレートの出力を要約するか分割送信に変更してください。
- ワークフロー ID の確認: n8n エディタで対象ワークフローを開き、URL などから ID を確認します。

---

補足:
- 本リポジトリのワークフローは Webhook ノードから即時に 200 を返し、その裏でメッセージ解析→Claude 実行→LINE 返信を並行実行します。
- 環境変数の参照は n8n 上で `{{$env.LINE_CHANNEL_ACCESS_TOKEN}}` として行っています。
