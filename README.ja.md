# CodexMulti

[English](README.md) · [한국어](README.ko.md) · **日本語**

<p align="center">
  <img src="assets/hero.png" width="100%" alt="CodexMulti — 1台のMacで複数のCodexアカウントを自動切り替え">
</p>

**1つのアカウントが利用上限に達しても、次のアカウントで作業を続けられます。**

CodexMultiは、複数のCodexアカウントをまとめて管理するmacOSメニューバーアプリです。
残りの利用枠を確認し、アカウントの順序を決めておけば、利用上限エラーが確認されたときに自動で切り替えます。

[ダウンロード](https://github.com/moonsunkim/codexmulti/releases/latest) · [変更履歴](CHANGELOG.md) · [セキュリティ](SECURITY.md) · [貢献ガイド](CONTRIBUTING.md)

[![CI](https://github.com/moonsunkim/codexmulti/actions/workflows/ci.yml/badge.svg)](https://github.com/moonsunkim/codexmulti/actions/workflows/ci.yml)

- **全アカウントを一覧で確認。** 残りの利用枠、上限のリセット時刻、利用可能なアカウントを1つの画面に表示します。メニューバーでは全体の残量を確認でき、**アカウント…**から一覧を開けます。
- **順序は一度設定するだけ。** アカウントをドラッグして希望の順序に並べます。利用上限エラーを受け取ると、次の利用可能なアカウントでリクエストを再試行します。
- **スイッチ1つで開始。** ローカルプロキシとNodeランタイムを同梱しています。アプリを開いている間は、アカウントの追加や再接続も自動で反映します。
- **認証情報はMac内に保存。** アカウントごとに独立したCodexディレクトリとキーチェーンのバックアップを使います。CodexMultiへの会員登録や外部サーバーへの接続設定は不要です。

## Failoverは何を解決する機能ですか？

コーディング中に1つのアカウントが利用上限に達すると、別のアカウントに利用枠が残っていても作業が止まることがあります。
自動切り替えがなければ、自分で別のアカウントを選び、リクエストを送り直す必要があります。

**Failoverは、利用上限エラーが確認されたときに、次の利用可能なアカウントで同じリクエストを自動再試行する機能です。**
アカウントを追加して順序を決め、**Failoverを使用**をオンにすると、対応するCodexリクエストがMac内のローカルプロキシを経由します。

たとえば、アカウントAが応答を開始する前に利用上限エラーを返した場合、同じリクエストをアカウントBで再試行します。
Bも上限に達していれば、次の利用可能なアカウントを試します。上限エラーのたびに手動でアカウントを切り替える手間を減らせます。

各アカウントの契約と利用上限は変わりません。すでに開始した応答を別のアカウントで再実行したり、すべてのエラーを再試行したりする機能ではありません。
詳しい条件は[アカウントが切り替わるタイミング](#アカウントはいつ切り替わりますか)をご覧ください。

## インストール

**macOS 26以降を搭載したApple Silicon Mac**と、ChatGPTでログインするCodex CLIが必要です。
アカウントの自動切り替えを利用するには、2つ以上のアカウントが必要です。

```sh
brew install --cask moonsunkim/tap/codexmulti
```

または[最新リリース](https://github.com/moonsunkim/codexmulti/releases/latest)をダウンロードしてください。
0.2.1以降のリリースはDeveloper ID署名とAppleの公証を取得しています。

<details>
<summary>インストールスクリプトまたは手動インストール</summary>

```sh
curl -fsSL https://raw.githubusercontent.com/moonsunkim/codexmulti/main/install.sh | bash
```

スクリプトは公開済みのSHA-256チェックサムを検証し、既存のアプリを`CodexMulti.app.previous`として保存します。
新しいアプリを`/Applications`にインストールし、バックグラウンドで開きます。Gatekeeperの隔離属性は保持します。

手動でインストールする場合は、`CodexMulti-<version>.zip`と対応する`.sha256`ファイルを同じディレクトリに保存し、
展開する前に次のコマンドで検証してください。

```sh
shasum -a 256 -c CodexMulti-<version>.zip.sha256
```

検証した`CodexMulti.app`を`/Applications`に移動して開きます。

</details>

## 2ステップで開始

1. **アカウントを追加。** **+**を押してアカウント名を入力し、公式のブラウザログインを完了します。利用するアカウントごとに繰り返してください。
2. **Failoverを使用をオンにする。** **設定**で有効にすると、アプリが同梱のプロキシを準備し、動作を確認してからCodexを接続します。

あとは通常どおりCodexを使えます。応答開始前に利用上限エラーが確認されると、同じリクエストを次のアカウントで試します。
一時停止中、認証に問題がある、または上限のリセット待ちのアカウントはスキップします。

アプリを開いている間は、アカウントの追加、再接続、順序変更を自動で反映します。プロキシの再読み込みが必要な変更は、
処理中のリクエストが完了してから適用します。メニューバーアプリを終了しても、正常に動作しているプロキシは引き続き実行されます。
Failoverをオフにすると、処理中のリクエストが完了した後でCodexの直接接続に戻します。

メニューバーの**アカウント…**から全アカウントを表示できます。
各アカウントのメニューでは、新しいリクエストに使うアカウントの指定や、自動切り替え対象からの一時除外と再開ができます。
すでに処理中のリクエストはそのまま続行します。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/accounts-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/accounts-light.png">
  <img alt="残りの利用枠、リセット時刻、各アカウントの状態を表示するCodexMultiの一覧" src="assets/screenshots/accounts-light.png">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/settings-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/settings-light.png">
  <img alt="Failoverスイッチと言語選択メニューを備えた設定画面" src="assets/screenshots/settings-light.png">
</picture>

利用量の更新間隔、表示する利用期間、テーマを選べます。
言語は**システム、English、한국어、日本語**に対応しています。上のスクリーンショットは英語表示です。

<details>
<summary>アカウントの詳細を見る</summary>

アカウントを展開すると、期間別の利用量、認証と自動切り替えの状態、最終更新時刻、報告されたリセットクレジットを確認できます。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/accounts-expanded-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/accounts-expanded-light.png">
  <img alt="利用期間、トークンの状態、更新時刻、リセットクレジットを示すアカウント詳細" src="assets/screenshots/accounts-expanded-light.png">
</picture>

スクリーンショットにはすべて架空のアカウントを使っています。

</details>

## アカウントはいつ切り替わりますか？

応答ストリームの開始前に、エラータイプが`usage_limit_reached`のHTTP `429`を受け取った場合、
またはWebSocketのハンドシェイクで同じ応答を受け取った場合にのみ切り替えます。1つのリクエストで各候補アカウントを試すのは最大1回です。

ネットワーク障害、`5xx`、中断されたストリーム、契約の不一致、`usage_not_included`、認識できない`429`ではリクエストを停止します。
開始済みの応答を別のアカウントで再実行することはありません。利用可能なアカウントがなくなると、無限に再試行せずエラーを返します。

アプリはアカウントの上限や契約を変更しません。プロキシの互換性はCodex CLIに合わせて管理しています。
更新前に[リリースノート](https://github.com/moonsunkim/codexmulti/releases/latest)を確認してください。

## アカウント情報はMac内に保存

テレメトリ、アクセス解析、CodexMultiが運営する制御サーバーはありません。認証、利用量の確認、推論はプロバイダーのサービスに直接接続します。
プロキシはループバックアドレスでのみ待ち受け、制御APIにはユーザーごとの非公開認証トークンを使います。

アカウントごとに独立したCodexホームを使用します。認証情報はローカルに保存し、キーチェーンにバックアップします。
個人用の`~/.codex/auth.json`は置き換えません。Failoverを有効にすると、`~/.codex/config.toml`内で
アプリが管理する2つのbase-URL設定だけを変更し、時刻付きのバックアップを残します。無効にすると直接接続に戻します。

セキュリティ上の信頼範囲とログの扱いについては、[セキュリティ](SECURITY.md)と[プロキシのセキュリティ](proxy/README.md#state-logs-and-security)をご覧ください。

## ソースからビルド

`PATH`にZig 0.16.0が必要です。Swift 6とmacOS 26 SDKを含むXcodeまたはCommand Line Tools、
およびmacOS 26を搭載したApple Silicon Macを用意してください。

```sh
./app/scripts/fetch-node.sh
./app/scripts/build-app.sh
./app/scripts/screenshots.sh
./app/scripts/verify-provenance.sh app/dist/staging/CodexMulti.app
./app/scripts/verify-bundled-proxy.sh app/dist/staging/CodexMulti.app
```

固定バージョンのNodeをSHA-256で検証し、コアを`aarch64-macos`オブジェクトにコンパイルしてSwift実行ファイルにリンクします。
`app/dist/staging/CodexMulti.app`に、Node実行ファイルとプロキシソースを含むアプリを作成します。
コアソースのハッシュ、ブリッジスキーマ、プロキシのコミットとファイルツリーのハッシュ、Nodeのハッシュを記録し、
`verify-provenance.sh`が実際のファイルから再計算して確認します。

テスト：

```sh
(cd core && zig build test && zig build test-bridge)
(cd app && CODEXMULTI_TEST_HEADLESS=1 swift test)
(cd proxy && npm test)
```

Swiftテストには必ず`CODEXMULTI_TEST_HEADLESS=1`を指定してください。通常の`swift test`はウィンドウを開きます。
CIはmacOSでZigコア、Nodeプロキシ、SwiftUIシェル、配布スクリプトを検証します。SwiftUIのジョブにはmacOS 26 SDKを使います。

署名とリリース用パッケージの作成は通常のビルドとは別です。`app/scripts/package-signed-macos.sh`はローカルの署名情報を確認し、
同梱Nodeからアプリ本体の順に署名します。出所情報や指定要件が一致しないバンドルは拒否します。

## 構成

| 構成要素 | 役割 |
| --- | --- |
| [SwiftUIアプリ](app/) | ウィンドウ、メニュー、アクセシビリティ、macOS連携 |
| [Zigコア](core/) | アカウント、バックグラウンド処理、安全な接続設定変更、すべてのUI文言 |
| [Nodeプロキシ](proxy/) | ローカルのリクエスト転送と利用可能なアカウントへの自動切り替え |

アプリは型付きの操作要求をコアに送り、返された状態を表示します。
プロキシはユーザーごとのLaunchAgentとして独立して動作するため、メニューバーアプリを終了してもリクエストの処理を続けられます。
プロキシと固定バージョンのNodeランタイムは、どちらもアプリに含まれています。

<details>
<summary>復旧、アンインストール、接続設定の手動修復</summary>

Failoverが有効な間、アプリは復旧を自動で再試行します。実行中のリクエストを待つ必要がある場合は、その理由を状態に表示します。
Failoverを無効にすると、それらのリクエストが完了した後にCodexの直接接続へ戻します。

アプリを削除する前にCodexクライアントを終了し、次を実行してください。

```sh
"/Applications/CodexMulti.app/Contents/Helpers/codexmulti-maintenance" prepare-uninstall
brew uninstall --cask codexmulti
```

同梱のヘルパーは、アプリが管理する2つの接続設定だけを復元し、正常に処理中のリクエストの完了を待ちます。
LaunchAgentの実行引数を厳密に確認したうえで、plistとサービスのインストール記録を削除します。
認証情報、利用履歴、リセット記録は再インストール用に保持します。Homebrewは削除時にこのヘルパーを自動実行します。
設定の競合や使用中のサービスが報告された場合は、問題を解決して再試行してからアプリを削除してください。
Homebrewによる更新や再インストールでも同じ整理処理を行うため、その後CodexMultiを開いてFailoverを再び有効にしてください。
`--zap`を使うと、保存したアカウントデータも削除されます。

アプリやヘルパーを実行できない場合は、`~/.codex/config.toml`をテキストエディターで開きます。
最上位に次の項目がある場合に限り、この2項目だけを削除し、ほかの設定は残してください。

```toml
chatgpt_base_url = "http://127.0.0.1:8787/backend-api/"
openai_base_url = "http://127.0.0.1:8787/backend-api/codex"
```

次に`launchctl print "gui/$(id -u)/dev.codexmulti.app.proxy"`で実行引数を確認します。
CodexMultiアプリの`Contents/Helpers/node`、`Contents/Resources/proxy/src/server.mjs`、`--config`、
自分のプロキシ設定を指している場合に限り、`launchctl bootout "gui/$(id -u)/dev.codexmulti.app.proxy"`で停止し、
`~/Library/LaunchAgents/dev.codexmulti.app.proxy.plist`を削除してください。
Codexクライアントを再起動して直接接続の設定を読み込ませます。共有設定ファイル全体を古いバックアップで上書きしないでください。

プロキシの制御にはユーザーごとの非公開認証トークンが必要です。通常のCodexプロキシ通信はローカルMacのユーザーとプロセスを信頼する設計です。
信頼できる環境で使用してください。詳細は[プロキシのセキュリティ](proxy/README.md#state-logs-and-security)をご覧ください。

</details>

## ライセンス

MIT — [LICENSE](LICENSE)をご覧ください。同梱Node.jsの告知事項は[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)にあります。

CodexMultiは独立したオープンソースプロジェクトです。OpenAIとの提携関係や、OpenAIによる公認・推奨はありません。
CodexはOpenAIの商標です。
