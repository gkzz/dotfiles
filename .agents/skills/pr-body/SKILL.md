---
name: pr-body
description: Draft or update a GitHub pull request body for this repository using .github/pull_request_template.md as the source format.
metadata:
  short-description: Draft PR bodies from the repo template
---

# PR Body

## Provenance

- Origin: Original skill authored for this global skills collection

Use this skill when asked to draft, rewrite, or update a pull request body for this repository.

Read `.github/pull_request_template.md` first and preserve its headings and order. Treat template comments as guidance only.

Gather enough context from git, changed files, the existing PR when available, and known test or CI results. Do not invent verification results.

Write the body primarily in Japanese while keeping the template's English headings unchanged. Keep bullets concrete and reviewer-relevant; use `- なし` for empty notes.

When grouping changes by commit, use a Markdown link whose label is the short commit hash and whose target is the full commit URL. Put the commit subject on the next line. Do not combine both in one heading; long headings are harder to scan.

```markdown
### [<short-sha>](https://github.com/gkzz/dotfiles/commit/<full-sha>)

`<commit subject>`

- 変更点
```

For this dotfiles repository, prefer nearby validation such as `make validate`, targeted `bash -n`, and relevant `--dry-run` commands when those results are available. If validation was not run, label it as `not run` with a short reason.

Do not edit the remote PR body unless the user explicitly asks to apply it. When they do, use `gh pr edit --body-file` or an equivalent `gh` command, then verify the updated body with `gh pr view`.
