# Nosia's vendored ruby_llm-mcp 1.0.1

## Provenance

- Upstream: <https://github.com/patvice/ruby_llm-mcp>
- Published gem: <https://rubygems.org/gems/ruby_llm-mcp-1.0.1.gem>
- Release metadata: <https://rubygems.org/api/v2/rubygems/ruby_llm-mcp/versions/1.0.1.json>
- Version: **1.0.1** (unchanged); published 2026-07-21.
- Archive SHA-256, verified against the metadata's `sha` on 2026-10-14:
  `22121bfdea1874935debdd9cee0235d02473885ce8347cf745a323f0707fd248`.
- License: MIT, copyright Patrick Vice; the published `LICENSE` and source
  notices are retained unchanged.

Fetched with `gem fetch ruby_llm-mcp --version 1.0.1` and unpacked with
`gem unpack ruby_llm-mcp-1.0.1.gem`, both under
`/tmp/opencode/nosia-rubyllm2-research`, outside the repository. The downloaded
archive, metadata response, and unpacked comparison copy stay outside Git.

The 120 imported files are byte-identical to the archive: `lib/ruby_llm/`,
`lib/generators/` (including every generator template), `README.md`, and
`LICENSE`. No runtime assets are omitted. The only excluded published files
are upstream development tasks `lib/tasks/release.rake` (publishing/tagging)
and `lib/tasks/smoke.rake` (runs upstream's unshipped specs). No caches,
archives, installed gems, or development checkout are vendored.

## Local patch and current boundary

This is a **locally patched dependency**, not upstream RubyLLM 2.0 support.
The published `ruby_llm (~> 1.9)` requirement excludes 2.0 and cannot be used
unchanged. The gemspec now requires **`ruby_llm (= 2.0.0)`**, the sole target
of the planned compatibility port. It does not claim compatibility with later
2.x releases. The root Gemfile uses this path dependency explicitly.

The archive contains no `.gemspec` file. `ruby_llm-mcp.gemspec` is reconstructed
from `Gem::Package.new(archive).spec`, retaining upstream identity, metadata,
Ruby requirement, require path, and other runtime dependency requirements.
Only the RubyLLM constraint and packaging file list are adapted. The file list
is local and deterministic, includes this note, and does not call Git.

**Task 3 only establishes provenance, packaging, and dependency resolution.**
No imported runtime source has been changed yet. The bridge's removed
`RubyLLM::Content` inheritance, attachment bytes, tool schema reader, and
prompt/resource/sampling conversions still require the narrow Task 7 port.
Do not deploy this intermediate dependency switch or interpret a passing
version assertion as working MCP compatibility. Application association/schema
adoption and token-reader updates also remain in Tasks 4–6.

## Maintenance and removal

1. Preserve the pristine archive hash above as the comparison base. Fetch and
   verify it outside the repository before reviewing or refreshing the patch.
2. Document each runtime file changed by Task 7 and its behavior here. Keep
   stdio, SSE, and streamable HTTP transports and security checks unchanged.
3. Run the MCP/local-engine compatibility tests without provider credentials,
   alongside the application accounting and migration verification gates.
4. For a future upstream release with RubyLLM 2.0 support, inspect its published
   gemspec, compare every patched boundary, and run those same tests before
   replacing the path dependency. Remove this vendor directory only once the
   upstream release fully replaces the local patch; do not merely loosen the
   version constraint or assume newer 2.x compatibility.
