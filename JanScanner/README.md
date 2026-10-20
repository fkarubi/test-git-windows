# JANスキャナー（iPhoneアプリ）

iPhoneのカメラでJANコード（EAN-13 / EAN-8）を読み取り、数字をCSVファイルに保存するアプリです。

## 機能
- カメラで連続スキャン（読み取ると「ピッ」という音と振動でお知らせ）
- チェックデジットで誤読を防止
- 同じコードの重複登録を防止（メニューから「重複を許可」に切り替え可能）
- 読み取るたびに CSV を自動保存
- 「CSV共有」ボタンから AirDrop・メール・ファイル保存などで書き出し
- 行を左にスワイプして削除、メニューから全件削除
- 写真を Mac のリレーに送って、バーコードが写っているかと位置を確認（連続スキャンとは別画面）

## CSV形式
保存先: 「ファイル」アプリ → このiPhone内 → JANスキャナー → `jan_codes.csv`

```
No,JANコード,読取日時
1,4901085089026,2026/10/09 10:15:30
```
UTF-8（BOM付き）で保存するため、Excelで開いても文字化けしません。

## 写真で確認（Mac のリレー）

オンデバイスの連続スキャンはそのままです。右上の写真アイコンから「写真で確認」を開くと、撮った写真またはライブラリの写真を、Tailscale 経由で Mac 上のリレーに送ります。

リレーは写真を TypeSafe に渡し、「バーコードがある確率」と「位置」だけを返します。TypeSafe の API キーは Mac にだけ置き、このアプリには入れません。アプリが知るのはリレーの URL と合言葉だけです。

店の商品・お客様・従業員の写真は使わないでください。自宅の物や、自分で作ったテスト画像で確認します。

### Mac 側

リレー（`typesafe-relay`）を Mac で起動しておきます。待ち受けは Tailscale の IP だけで、例は `http://100.127.247.83:8787` です。

```bash
curl http://100.127.247.83:8787/health
# {"ok":true}
```

合言葉は Mac のキーチェーン（サービス `typesafe-relay`、アカウント `relay-token`）に入れます。作り方の例:

```bash
python3 -c 'import secrets;print(secrets.token_urlsafe(32), end="")' | pbcopy
security add-generic-password -s typesafe-relay -a relay-token -w
```

値はコマンド履歴に残さないよう、`-w` は最後に値なしで実行してプロンプトへ貼ります。iPhone へはユニバーサルクリップボードや AirDrop で渡し、渡したあとはクリップボードを別の文字で上書きします。チャットや Git には書かないでください。

### iPhone 側

1. App Store の Tailscale を入れ、Mac と同じ tailnet に接続する
2. アプリの「写真で確認」→ 歯車 → リレーの URL（初期値 `http://100.127.247.83:8787`）
   - ベース URL です。末尾の `/barcode` は不要です
   - MagicDNS 名も使えます（例: `http://自分のMac.tailnet名.ts.net:8787`）
3. 合言葉を入力して「合言葉を保存」
   - 保存先は iOS のキーチェーンだけです。UserDefaults やソースには書きません
   - 保存後は再表示しません。変えるときだけ入力します
4. 「写真を撮る」または「写真を選ぶ」

確率が **50% 以上**（コード上の定数 `RelayVerdict.presenceThreshold`）なら「バーコードあり」とし、返ってきた枠を写真の上に赤く描きます。50% 未満のときは枠を描きません。枠の数値は、サーバーが正立・縮小した画像に対する 0〜1 の割合です。

写真ライブラリはシステムの選択画面（PHPicker）なので、ライブラリ全体への許可は求めません。カメラは JAN の読み取りと、この確認写真の両方に使います。

### うまくいかないとき

| 表示 | 意味 |
|---|---|
| 接続がタイムアウトしました…Tailscaleがオフ | iPhone の Tailscale が切れていることが多いです。先に Tailscale アプリで接続してください |
| リレーに接続できません | 同じ tailnet にいるか、URL の IP とポートを確認してください |
| 合言葉が違います（401） | 保存した合言葉が Mac 側と違います |
| 写真を送れませんでした（400） | 画像として読めない、または小さすぎます |
| 写真が大きすぎます（413） | 16MB を超えています |

送信の前に認証なしの `/health` を短い制限時間で確認します。ここがタイムアウトしたときは写真を送りません。ヘルスチェックが通ったあとのタイムアウトは、リレーには届いたが判定が返らなかった、という意味です。

### HTTP と App Transport Security

リレーは Tailscale の中だけで平文 HTTP です。iOS はそれを既定では止めます。

- 例外ドメインに IP アドレスは長いあいだ書けませんでした。iOS 17 以降は IP と CIDR を書けます
- `NSAllowsLocalNetworking` が通すのは RFC1918（10/8、172.16/12、192.168/16）や `.local` などで、Tailscale の `100.64.0.0/10`（CGNAT）は含まれません
- `NSAllowsArbitraryLoads` は全ホストの HTTP が開くので使いません。`NSAllowsLocalNetworking` と併記すると、iOS 10 以降では ArbitraryLoads の方が無視されます

そのため `project.yml` の例外は次だけです。

- `100.127.247.83` … 初期 URL の個別 IP。古い iOS 17 で CIDR がマッチしない場合の保険です
- `100.64.0.0/10` … Tailscale の IPv4 全体。設定で別の 100.x に変えても通ります。iOS 16 は IP 宛ての接続を ATS が既定で許可し、iOS 17 以降はこの CIDR が必要です
- `ts.net`（サブドメインを含む）… MagicDNS 名。公開名なので IP の例外では通りません

アプリ自身も、送信先をこの範囲（`100.64.0.0`〜`100.127.255.255`、または `名前.tailnet.ts.net`）に限っています。初期の iOS 17 で CIDR 例外が効かない端末は、MagicDNS 名に切り替えてください。

`xcodegen generate` のあと、生成された `JanScanner/Info.plist` の `NSAppTransportSecurity` がこの3件になっていることを確認できます（この plist は生成物なので Git には入れません）。

## ビルド方法（Mac が必要）
1. Xcode 15 以降と [XcodeGen](https://github.com/yonaskolb/XcodeGen) をインストール
   ```
   brew install xcodegen
   ```
2. このフォルダでプロジェクトを生成して開く
   ```
   cd JanScanner
   xcodegen generate
   open JanScanner.xcodeproj
   ```
3. Xcode で「Signing & Capabilities」の Team に自分の Apple ID を設定
   （必要なら Bundle Identifier を `com.自分の名前.JanScanner` などに変更）
4. iPhone を USB で接続して ▶ で実行
   - 初回は iPhone の「設定 → 一般 → VPNとデバイス管理」で開発元を信頼してください
   - 連続スキャンは実機のカメラが必要です
   - 「写真で確認」はシミュレータでも、写真を選べば画面の流れを確認できます（カメラ撮影は実機だけです）

単体テスト（合成のバイト列と JSON だけ。写真ファイルは使いません）:

```
xcodebuild test -scheme JanScanner -destination 'platform=iOS Simulator,name=iPhone 16'
```

宛先のシミュレータ名は、入っているものに読み替えてください。

対応OS: iOS 16 以降
