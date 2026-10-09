# JANスキャナー（iPhoneアプリ）

iPhoneのカメラでJANコード（EAN-13 / EAN-8）を読み取り、数字をCSVファイルに保存するアプリです。

## 機能
- カメラで連続スキャン（読み取ると「ピッ」という音と振動でお知らせ）
- チェックデジットで誤読を防止
- 同じコードの重複登録を防止（メニューから「重複を許可」に切り替え可能）
- 読み取るたびに CSV を自動保存
- 「CSV共有」ボタンから AirDrop・メール・ファイル保存などで書き出し
- 行を左にスワイプして削除、メニューから全件削除

## CSV形式
保存先: 「ファイル」アプリ → このiPhone内 → JANスキャナー → `jan_codes.csv`

```
No,JANコード,読取日時
1,4901085089026,2026/10/09 10:15:30
```
UTF-8（BOM付き）で保存するため、Excelで開いても文字化けしません。

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
   - シミュレーターにはカメラがないため、実機で実行してください

対応OS: iOS 16 以降
