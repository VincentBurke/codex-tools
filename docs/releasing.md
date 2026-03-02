# Releasing Codex Tools

This repository publishes tagged releases and updates Homebrew automatically.

## Required Secrets

Configure this secret in `VincentBurke/codex-tools` repository settings:

- `HOMEBREW_TAP_TOKEN`: fine-grained personal access token with `contents:write` access to `VincentBurke/homebrew-tap`.

## Tap Prerequisites

- Tap repository exists: `VincentBurke/homebrew-tap`.
- Tap repository is accessible by the token in `HOMEBREW_TAP_TOKEN`.
- Tap users install from: `brew tap VincentBurke/tap`.

## Release Trigger

- Workflow triggers on `v*` tags.
- Version is derived by removing leading `v` from the tag.
- Allowed version characters: `0-9`, `A-Z`, `a-z`, `.`, `_`, `-`.

## End-to-End Flow

1. Push a tag such as `v1.2.3` to `origin`.
2. `Release` workflow builds two archives:
   - `codex-tools-<version>-arm64.tar.gz`
   - `codex-tools-<version>-x86_64.tar.gz`
3. Workflow creates SHA256 files for both archives.
4. Workflow creates or updates GitHub Release `v<version>` and uploads assets (`--clobber` on reruns).
5. Workflow checks out `VincentBurke/homebrew-tap`.
6. Workflow rewrites `Formula/codex-tools.rb` with the new release URLs and checksums.
7. Workflow commits and pushes formula updates to tap default branch.

## Local Release Command

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

## Troubleshooting

### Release job fails at tap update

- Confirm `HOMEBREW_TAP_TOKEN` exists and is valid.
- Confirm token has `contents:write` permission for `VincentBurke/homebrew-tap`.
- Confirm the tap default branch is not protected against the configured automation identity.

### Workflow rerun behavior

- Rerunning a release tag re-uploads assets with `--clobber`.
- Formula updates are deterministic; if there is no content change, no commit is created.

### Artifact checksum mismatch during install

- Verify release artifacts were uploaded from the same workflow run that generated checksums.
- Re-run the tag workflow to regenerate assets and formula checksum values.
