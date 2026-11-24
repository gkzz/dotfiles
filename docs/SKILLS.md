# Agent Skills Management

スキルを追加・更新する開発者と、その作業をするエージェント向けの管理方針です。

スキルは `.agents/skills/<name>/SKILL.md` に配置し、`mise.toml` で `~/.agents/skills/<name>` へのリンクを管理します。
各スキルは Agent Skills の仕様に準拠し、frontmatter に `name` と `description` を定義します。
本文の言語、見出し、構成、ワークフロー、`references/` の有無は、スキルの目的に応じて決めます。

## Third-Party Skills

- 外部スキルを参考・改変した場合は、出典 URL を記録します。
- 必要に応じて、参照したコミットやバージョン、変更内容を記録します。
- 原著作物のライセンスを確認し、必要な著作権表示とライセンス文書を保持します。
- 記録先は `SKILL.md` の metadata、本文、またはリンク先の文書とし、metadata の項目やスキル本文の構成は統一しません。

外部スキルを改変するときは、元の有用な設計と動作を維持することを優先し、形式の統一だけを目的とした既存スキルの書き換えは行いません。

## renodash-dashboard Distribution

`renodash-dashboard` スキルは、[renodash のサンプル（7b956e9）](https://github.com/gkzz/renodash/blob/7b956e97cf2ca9d8818936a18ffdfa257f1738e8/examples/skills/renodash-dashboard/SKILL.md)を正本とします。dotfiles には配布用のコピーを置き、更新時に正本と照合します。mise はそのコピーを `~/.agents/skills/renodash-dashboard` にリンクします。renodash リポジトリを clone する必要はありません。
