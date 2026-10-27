# Portable MLIR Toolchain Agent Guide

Read the relevant parts of [README.md](README.md) and the affected workflow or
script before changing a build. This repository builds and packages upstream
LLVM/MLIR.

## Repository layout

- `scripts/toolchain/` contains shared and platform-specific build scripts.
- `.github/workflows/` builds, tests, and publishes the platform archives.
- `tests/integration/` contains the installed-toolchain smoke test.
- `CHANGELOG.md` records dated releases and their distributed versions.

## Working principles

- Inspect the working tree first and preserve existing changes. Keep each diff
  focused; avoid unrelated upgrades or formatting.
- Trace a change from script inputs through workflow inputs, artifact names,
  installation tests, and the consumers in
  [setup-mlir](https://github.com/munich-quantum-software/setup-mlir).
- Preserve platform differences: Linux uses manylinux containers, macOS builds
  target Apple Silicon, and Windows releases use `clang-cl` and Release mode.
  Keep shared behavior in shared scripts where possible.
- Preserve both assertion-enabled and `_noassert.tar.zst` SDK variants. Their
  headers and libraries must stay paired; a passing build of one variant does
  not validate the other.
- Keep failures visible across shell and PowerShell scripts and GitHub Actions.
  Check archive contents and installed-toolchain behavior, not only build exit
  codes.
- Document current contracts and non-obvious reasons in short, direct prose.
- Keep generated binaries, archives, local build directories, credentials, and
  machine-specific settings out of commits.

## Validation

- Run `uvx prek run -a` before submitting a PR. For a small edit, run the
  relevant hooks on changed files while working and rerun them after fixes.
- For build or workflow changes, validate affected platforms and both assertion
  variants. Use the installation smoke test in `tests/integration/` to check the
  installed SDK. A documentation-only change does not need a toolchain rebuild.
- Inspect the final diff and working-tree status. Report local passes, skipped
  checks, infrastructure failures, and hosted CI separately. Check the final PR
  head before calling it green.

## Release preparation

- Use a dedicated PR based on current `main`. Check the latest repository
  release and the exact upstream `llvmorg-*` tag before choosing the LLVM
  version. Use the intended release date in `YYYY.MM.DD` form for the repository
  tag; do not treat the LLVM version as the repository release tag.
- Keep ordinary development changes out of `CHANGELOG.md` until release
  preparation unless explicitly requested. Add a dated section below
  `Unreleased`, with the LLVM tag and the actual zstd and mold versions under
  `Distribution`. Include only changes merged since the previous release. Give
  independent user-visible changes separate entries, with PR links and
  contributor credits. Preserve historical release entries.
- Update the `Unreleased` comparison and add the new release link at the bottom
  of `CHANGELOG.md`. Update the default LLVM ref, fallback expressions, and
  input examples throughout `.github/workflows/`. Update release-date examples
  and any current documentation or script references. Do not rewrite older
  release dates or unrelated container-image version tags.
- Validate the changelog and workflows with `uvx prek run -a` and
  `git diff --check`. Review the PR diff for stale current-version references. A
  PR check that skips platform builds does not qualify release artifacts.
- After the preparation PR is merged, create and push a signed annotated
  repository tag at the merged revision before dispatching the release workflow.
  Verify the tag and supply the intended LLVM ref, release tag, and release
  notes to the workflow. Confirm the completed platform builds, installation
  tests, assertion variants, and published assets before reporting a release
  complete.

## Git and pull requests

- Follow the repository's gitmoji subject style. Sign commits and annotated
  tags, and verify signatures before pushing. Record AI help with `Assisted-by`,
  never an AI `Co-authored-by` trailer.
- Assign submitted PRs to `@burgholzer` and apply appropriate existing labels.
  Describe the change and its validation without claiming pending CI has passed.
