# sharex-mac

[ShareX](https://github.com/ShareX/ShareX) のキャプチャ機能を macOS 向けに Swift で作り直したメニューバーアプリ。

## ビルド

```sh
./build.sh --install
```

`~/Applications/ShareX.app` にインストールされる。初回起動時に「システム設定 > プライバシーとセキュリティ > 画面収録とシステムオーディオ録音」で許可し、再起動する。

## ホットキー

| 操作 | ホットキー |
|---|---|
| 範囲キャプチャ | ⌃⌥⇧4 |
| ウィンドウキャプチャ | ⌃⌥⇧5 |
| 全画面キャプチャ | ⌃⌥⇧3 |

画像は `~/Pictures/ShareX/` に保存される。

## ライセンス

GPL-3.0。アイコンと効果音は ShareX のものを使用している。
