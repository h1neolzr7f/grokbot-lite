# CI

The intended GitHub Actions workflow is [`.github/ci.yml.example`](../.github/ci.yml.example)
(shellcheck + bats on ubuntu-24.04 / 22.04 / arm, plus `@electron/fuses` cross-check).

It ships as an *example* (not `.github/workflows/ci.yml`) because the token used for the
initial public push lacked the GitHub OAuth `workflow` scope. After
`gh auth refresh -s workflow` (or a PAT with that scope):

```bash
mkdir -p .github/workflows
cp .github/ci.yml.example .github/workflows/ci.yml
git add .github/workflows/ci.yml && git commit -m "ci: enable GitHub Actions" && git push
```

Until then: `make lint test` locally (58 bats + shellcheck).
