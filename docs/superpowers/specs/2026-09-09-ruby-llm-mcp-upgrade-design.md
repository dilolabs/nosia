# ruby_llm-mcp 1.0.1 Upgrade

## Goal

Upgrade the locked `ruby_llm-mcp` dependency from `0.7.0` to `1.0.1`, the
latest stable release identified by the project release notes, and confirm
that Nosia's existing MCP behavior remains compatible.

## Scope

- Update the dependency resolution in `Gemfile.lock` to `ruby_llm-mcp 1.0.1`.
- Preserve the existing unconstrained `Gemfile` declaration and unrelated
  dependency versions where Bundler allows it.
- Run the MCP-focused tests first, then the full Rails test suite.
- Make application changes only when a failing test demonstrates a required
  compatibility adjustment.
- Leave unrelated worktree changes untouched.

## Approach

Use a conservative Bundler update for `ruby_llm-mcp`, allowing only dependency
changes required to resolve version `1.0.1`. Inspect the resulting lockfile
for unexpected upgrades. If tests fail, add a focused regression test before
making the smallest compatible application change.

## Verification

The upgrade is successful when:

1. `Gemfile.lock` records `ruby_llm-mcp (1.0.1)`.
2. MCP model, controller, and integration tests pass.
3. The full Rails test suite passes.
4. Any compatibility fix is covered by a focused test.
