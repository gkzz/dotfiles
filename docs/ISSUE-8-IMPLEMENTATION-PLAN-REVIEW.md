# Issue #8 実装計画のレビュー結果

対象計画: [ISSUE-8-IMPLEMENTATION-PLAN.md](ISSUE-8-IMPLEMENTATION-PLAN.md)

レビューの指摘は実装計画へ反映済み。実装時は計画書を正とし、このファイルは判断の経緯を調べるときに使う。

## 取り込んだ指摘

### `run_repository_mise` は install への影響も確認する

`run_repository_mise` は check と install の `apply_mise_tools` から呼ばれる。低レベルの実行関数と位置づけ、表示方法は呼び出し元で決める。

あわせて、install の正常系と既存のエラー処理を壊さないことを完了条件に追加した。

### check 用の preflight 出力を分ける

共通の `preflight_error` をそのまま使うと、状態不一致と実行エラーを表示から区別できない。install / uninstall の `error:` は残し、check から呼ぶ validator には専用の報告経路を設ける。

前提が欠けている検査だけを止め、同じ原因を preflight と後続処理から重ねて表示しないことも計画へ加えた。

### `readlink` の fake command は対象を絞る

すべての `readlink` を失敗させると、symlink 診断以外の処理まで巻き込む。対象 destination またはテスト用の環境変数に一致した呼び出しだけを失敗させ、それ以外は本物のコマンドへ渡す。

### Homebrew 不在は実行エラーとして表示する

`brew` が見つからない場合は、現行の `check failed:` から `check error:` へ変更する。`brew bundle check` の非ゼロは package 不足を示す通常の結果として、状態不一致のまま扱う。

### dangling symlink と source 不在の判定順を固定する

expected target を指す dangling symlink は、symlink 単体では正常と判定する。source の不在は、その前に行う repository 検証で報告する。

### cleanup の正常系と異常系を分けて試す

正常終了時は一時 directory が残らないことを確認する。cleanup に失敗した場合は `check error:` と終了コード `1` を確認し、テストで残した directory は harness 側で削除する。

### 利用者向けドキュメントも同時に更新する

`check failed:` / `check error:` を公開する表示形式として扱うため、`docs/TROUBLESHOOTING.md` と `docs/OPERATIONS.md` の更新を実装項目に含めた。README は操作方法や管理対象が変わらない限り更新しない。

## 条件を変えて取り込んだ指摘

### mise directory 全体の snapshot は比較しない

実際の mise は cache や state を更新する場合がある。directory 全体の checksum 比較は結果が安定しないため、採用しなかった。

代わりに、次を確認する。

- dotfiles が managed state を変更しない
- source の config / lock を変更しない
- check 用の lifecycle lock を作らない
- 正常終了時に isolated temporary directory を残さない

fake mise の call log はテスト観測用なので比較対象から外す。

## 今回は扱わない内容

- 状態不一致と実行エラーで終了コードを分ける
- `PREFLIGHT_FAILED` を全面的に作り直す
- `brew bundle check` の出力を解析し、package 不足と brew 内部障害を判別する

いずれも Issue #8 の完了には必要ない。必要になった時点で別 Issue として検討する。

## 結論

レビューで実装前に決めるべき点は、計画書へ反映済み。実装は [ISSUE-8-IMPLEMENTATION-PLAN.md](ISSUE-8-IMPLEMENTATION-PLAN.md) に沿って進められる。
