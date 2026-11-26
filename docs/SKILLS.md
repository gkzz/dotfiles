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

## renodash Skill Distribution

renodash の [examples/skills](https://github.com/gkzz/renodash/tree/main/examples/skills) を正本とし、dotfiles で `renodash-dashboard` と `renodash-weekly-review` の配布用コピーを管理します。参照したコミットは各スキルに記録します。更新時は正本と照合します。各スキルが使うオプションを、mise で固定した CLI がサポートしていることも確認します。

mise は各コピーを `~/.agents/skills/<name>` にリンクします。スキルの利用には renodash CLI と認証済みの `gh` が必要です。
