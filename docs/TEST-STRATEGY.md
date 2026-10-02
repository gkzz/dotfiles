# テスト戦略

Lint、dry-run、隔離HOMEでmakeターゲットを順に実行するライフサイクル確認を中心にします。個別の内部処理を網羅する単体テストは行わず、ライフサイクル確認では再現しにくい既存ファイル保護とmise設定の隔離だけを境界テストとして残します。

## 自動テスト

テストピラミッドの上から、対象範囲が広い順に並べています。

| レイヤー | テスト | 確認すること |
| --- | --- | --- |
| Lint | [lint.yml](../.github/workflows/lint.yml)、`make lint` | シェル構文と静的解析 |
| Dry-run | [test.yml](../.github/workflows/test.yml) | mise bootstrap がdry-runで完了すること |
| ライフサイクル | [CI](../.github/workflows/e2e_smoke.yml) | Ubuntu/macOSでmake install、install-apply、verify、uninstall、uninstall-applyを隔離HOME上で順に実行 |
| 境界テスト | [dotfiles-lifecycle.sh](../tests/integration/dotfiles-lifecycle.sh) | 既存ファイルとの競合で停止し、内容を上書きしないこと。HOME外の変更を防ぎ、miseへ`--force`を渡さないこと |
| 境界テスト | [mise-isolation.sh](../tests/integration/mise-isolation.sh) | 呼び出し元、HOME、リポジトリ内の追加設定がmiseの検査へ混入しないこと |

`make ci` はLintと境界テストを実行します。ライフサイクルの一連の動作は、pull requestのworkflowで確認します。

workflowではHOME、mise data、state、configを一時ディレクトリに隔離し、Homebrewを省略します。miseを準備した後、installのdry-run/apply、verify、uninstallのdry-run/applyを順に実行します。uninstall後は管理対象リンクが存在しないためverifyを実行しません。

## 自動テストで確認しないこと

内部関数の網羅、CLI全オプションの組み合わせ、エラーメッセージ全文、verifyの全異常パターン、全パッケージの導入成功、CI未実施OSでの動作、あらゆる状態での冪等性とuninstall安全性は保証しません。mise DotfilesやGit、Dockerの仕様は再実装して確認しません。実際の利用者HOMEへの適用、Homebrewの実インストール、Secretlintの検出精度も自動テストの対象外です。実HOMEに適用する場合は、dry-runの計画と競合を確認してください。

機密情報の検出はローカルのpre-commitに設定したsecretlintで行い、CIでは独立したSecret Scanを実行しません。pre-commitの未実行や`--no-verify`によるスキップは保証対象外です。

未保証の動作で不具合が起きた場合は必要に応じて修正・検証します。特に既存データを破壊する可能性がある不具合には、再発防止の確認を追加します。

## 検証方針

| 対象 | 保証する範囲 | 手段 |
| --- | --- | --- |
| 構文・静的解析 | シェル構文と静的解析で検出できる問題 | Lint |
| dry-run | セットアップ処理が変更を加えず完了すること | CI dry-run、ライフサイクル確認 |
| install / verify / uninstall | 隔離環境での基本ライフサイクル | CI workflow |
| 既存ファイル | 代表的な競合で停止し、内容を維持すること | 境界テスト |

正常系の一連の動作はライフサイクル確認で扱い、個別の境界テストには重ねて持ちません。
