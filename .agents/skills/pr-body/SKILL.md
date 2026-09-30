---
name: pr-body
description: Draft or update a GitHub pull request body for this repository using .github/pull_request_template.md as the source format.
metadata:
  short-description: Draft PR bodies from the repo template
---

# PR Body

Use this skill when asked to draft, rewrite, or update a pull request body for this repository.

Read `.github/pull_request_template.md` first and preserve its headings and order. Treat template comments as guidance only.

Gather enough context from git, changed files, the existing PR when available, and known test or CI results. Do not invent verification results.

Write the body primarily in Japanese while keeping the template's English headings unchanged. Keep bullets concrete and reviewer-relevant; use `- なし` for empty notes.

Do not edit the remote PR body unless the user explicitly asks to apply it. When they do, use `gh pr edit --body-file` or an equivalent `gh` command, then verify the updated body with `gh pr view`.
