# sharex-mac

[English](README.md)

[ShareX](https://github.com/ShareX/ShareX) を参考に Swift で一から作った、macOS 用の非公式なスクリーンキャプチャアプリ。メニューバーに常駐する。ShareX Team とは関係がなく、公認も受けていない。

![範囲キャプチャ](docs/region-capture.png)

![画像履歴](docs/image-history.png)

## 機能

- 静止させた画面の上での範囲キャプチャ。ウィンドウの自動検出、拡大鏡、ピクセルサイズ表示つき
- 最前面ウィンドウのキャプチャ（影なし）
- マウスがあるディスプレイの全画面キャプチャ
- キャプチャ後の処理: ファイル保存、クリップボードへのコピー、通知、サウンド
- 画像履歴ウィンドウ: サムネイル一覧、ファイル名での絞り込み、右クリックメニュー（開く、Finder で表示、コピー、ゴミ箱に入れる）
- ログイン時の起動
- 英語と日本語の UI

## 動作環境

- macOS 14 以降
- Xcode または Xcode Command Line Tools（Swift 5.10 以降）

## ビルドとインストール

```sh
git clone https://github.com/sofuetakuma112/sharex-mac.git
cd sharex-mac
./build.sh --install
```

`~/Applications/sharex-mac.app` にインストールされる。初回起動時に「システム設定 > プライバシーとセキュリティ > 画面収録とシステムオーディオ録音」で sharex-mac を許可し、アプリを再起動する。

`--install` を付けない `./build.sh` は `build.noindex/sharex-mac.app` を作るだけ。テストは `swift test` で実行する。

## ホットキー

| 操作 | ホットキー |
|---|---|
| 範囲キャプチャ | ⌃⌥⇧4（control + option + shift + 4） |
| ウィンドウキャプチャ | ⌃⌥⇧5 |
| 全画面キャプチャ | ⌃⌥⇧3 |

範囲キャプチャでは、ドラッグで範囲を選ぶか、ウィンドウをクリックしてそのウィンドウを撮る。Return で画面全体、Esc か右クリックで中止。

## 保存先

`~/Pictures/sharex-mac/` にランダムな 10 文字のファイル名で保存する。保存先は次のコマンドで変えられる。

```sh
defaults write io.github.sofuetakuma112.sharex-mac screenshotsFolder ~/Desktop/Captures
```

## 既知の制限

- ホットキーはまだ変更できない
- 全画面キャプチャはマウスがあるディスプレイだけで、全ディスプレイをまとめては撮れない
- 署名・公証済みの配布版はなく、ソースからビルドする必要がある
- ビルドは ad-hoc 署名なので、macOS はビルドし直すたびに別のアプリとして扱い、画面収録の許可をやり直す必要がある。`SIGN_IDENTITY` に署名用の証明書を指定すれば避けられる: `SIGN_IDENTITY="My Certificate" ./build.sh --install`
- 注釈エディタ、アップロード、画面録画など ShareX の機能の多くは未実装

## ライセンス

Copyright (C) 2026 Sofue Takuma

[GNU General Public License v3.0](LICENSE) で公開する。

`Resources/CaptureSound.wav` と `Resources/TaskCompletedSound.wav` は [ShareX](https://github.com/ShareX/ShareX) のもの（Copyright (c) 2007-2026 ShareX Team、GPL-3.0）。
