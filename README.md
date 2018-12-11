# お掃除おじさん bot

お掃除の時間を Idobata に通知してくれるお掃除おじさん bot のソースコード。

毎週水曜（祝日除く）の 13 時からお掃除なので、08:50 と 12:50 に掃除の時間を通知する。

`PureScript --|transpile|--> JavaScript --|deploy|--> Google Apps Script --|fetch(POST)|--> Idobata` という流れ。

## デプロイまでの流れ

1. クローンする
   - `git clone https://github.com/taiju/oso-bot`
   - `cd oso-bot`
2. いろいろインストールする
   - `npm install`
   - `npx bower install`
3. clasp をセットアップする
   1. [OPTION] `npx clasp login` する
   2. `npx clasp create YOUR-APP-NAME` する
   3. `.clasp.json` の `rootDir` を `dist` に設定する
   4. `appscript.json` を `dist/appsscript.json` に移動する
      - `timeZone` は `Asia/Tokyo` に修正する
4. [OPTION] `src/Main.purs` （PureScript）を修正する
5. [OPTION] 公開する（GAS で実行する）関数を `dist/index.js` に書く
6. ビルドする
   - `npm run build`
7. プッシュする
   - `npx clasp push`
8. [OPTION] デプロイする
   - `npx clasp deploy`

## プッシュ後に必要な作業

スクリプトエディターを開いて（`npx clasp open`）、下記の作業をする。

1. 下記のスクリプトプロパティを定義する
   - `idobataHookUrl`
     - 投稿先の Idobata Hooks の URL を指定する
   - `message`
     - 投稿するメッセージ（例: `@all 今日は掃除の日です。`）
   - `firstOfTheMonthMessage`
     - 月初に投稿するメッセージ（例: `@all 月初なので○○も掃除しましょう。`）
2. 指定日時のトリガーを作成するトリガーを作成する（デプロイの度に必要）
   - `index.gs` の `setUp` 関数を実行する
