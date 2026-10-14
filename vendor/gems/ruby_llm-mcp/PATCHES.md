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

The 120 imported files were initially byte-identical to the archive: `lib/ruby_llm/`,
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

### Task 7 runtime port (2026-10-14)

The supported RubyLLM target remains **exactly 2.0.0**, not arbitrary 2.x.
These are the complete imported-source differences from the archive above:

| File relative to this directory | Local adaptation |
| --- | --- |
| `lib/ruby_llm/mcp/attachment.rb` | Strict base64 decode into `StringIO`, invoke the parent with filename `mcp-attachment`, then retain the declared MIME type. Inherit real `content`, `encoded`, `source`, `config`, and `byte_size`; malformed base64 raises rather than becoming a path or URL. |
| `lib/ruby_llm/mcp/content.rb` | Ordinary bridge-owned text/attachments value, not a removed core subclass or global shim. Accept only already-built attachments (single or array, compacting nils). `to_tool_result` returns text or the supported string/attachment array; `to_message(role:)` separates the two fields. |
| `lib/ruby_llm/mcp/configuration.rb` | Add the application-owned `resource_url_validator` callback. Fresh/reset configurations leave it nil, so HTTP resource reads fail closed until a policy is explicitly installed. |
| `lib/ruby_llm/mcp/tool.rb` | Expose the full nested schema through `parameters_schema` and the corresponding `to_h` key. Convert every text/image/audio/embedded-resource/resource-link block; preserve all files, first and last. Structured JSON remains authoritative, including with accompanying attachments; retain output-schema validation and error hashes. Return only real RubyLLM-supported tool result types. |
| `lib/ruby_llm/mcp/prompt.rb` | Build real messages with separate text/files. Read standard `data`/`mimeType` media fields, retaining the upstream legacy field fallback, and consume embedded resource contents without rereading their URI. For explicit `ask`, initiate public `generate` only when `complete?` says no pending work, then run `complete` to finish tools or pause for approval. User-ended history resumes the ordinary loop without an extra generation. |
| `lib/ruby_llm/mcp/resource.rb` | Include converted messages, never a content value in `Message#content`. Every direct HTTP(S) fetch first requires a callable URL validator returning truthy approval; missing/rejecting policy raises `ConfigurationError`, and policy exceptions propagate before network I/O. Then retain `HTTPX.get`, check `raise_for_status`, and return a real `MCP::Result` containing the body's String value. HTTP status/transport failures propagate as their original HTTPX exceptions. URI dispatch is unchanged; vendor code does not reference the host application's URL-guard class. |
| `lib/ruby_llm/mcp/sample.rb` | Convert sampling inputs into real messages with separate attachments; explicitly request one response with public `Chat#generate`, including assistant-prefilled/system-only history. |
| `lib/ruby_llm/mcp/handlers/concerns/sampling_actions.rb` | Same conversion and explicit single generation for handler-based sampling, including system instructions. |
| `lib/ruby_llm/mcp/native/messages/responses.rb` | Remove the last removed-core-content type check. Serialize actual message text and attachments, using base64 wire data and `finish_reason`. Keep singular responses for one block. Multiple blocks require MCP 2025-11-25 or newer; older protocols explicitly raise `InvalidFormatError` rather than silently losing files or sending an invalid array. |
| `lib/ruby_llm/mcp/native/client.rb` | Pass the already-negotiated version to that response formatter; no transport or negotiation algorithm change. |
| `lib/generators/ruby_llm/mcp/oauth/templates/views/show.html.erb` | Mechanical `params_schema` → `parameters_schema` reader rename only; no generated UI redesign. |

The local gemspec constraint/file-list adaptation described above is unchanged.
All other imported files remain pristine. No official SDK replacement, new
transport, transport implementation edit, auth/config rewrite, schema migration,
or RubyLLM core monkey patch is introduced. Stdio opt-in and public-URL validation
remain in the application's `McpServer`. The app's local adapter now uses
`Tool.parameters`; server tool invocation uses keywords with a plain string-keyed
Hash. Only the tool endpoint's `arguments` JSON object is permitted/normalized,
separately from record attributes and tenant scoping.

Compatibility tests call the real bridge and 2.0 `Tool.split_result`, real
message construction/persistence, and actual provider media serialization.
Network/physical transport I/O uses canned fakes. The generation contracts leave
the provider, protocol, complete/generate loops, streaming parser, and persistence real.
Original stdio/SSE/streamable/streamable_http class selection, command/env,
URL/headers, lifecycle, capability errors, and application security guards are
covered. This is **not** a live-server interoperability certification or a
deployment approval; see `docs/upgrades/ruby-llm-2.md` for exact task evidence.

The Task 7 specification-review follow-up adds canned **real HTTPX response/body
objects** for both HTTP and HTTPS links and direct resource inclusion. These
exercise public bridge APIs, metadata registration/caching, surrounding text,
structured results plus all files, status errors, and transport errors. The
initial `git://`-only contract did not cover the raw-Hash HTTP reader defect;
that defect is fixed in the already-listed `resource.rb`. The subsequent quality
review also adds `configuration.rb`, making the final inventory **11 modified
imported files / 109 pristine files**. HTTP(S) is not
rerouted through MCP `resource_read` or a replacement transport.

### Task 7 quality-review security and JSON boundaries

The host app installs `config.resource_url_validator = ->(url) { UrlGuard.verify!(url) }`
in `config/initializers/ruby_llm.rb`. This enforces Nosia's existing outbound
policy for resource links, including links beside plain text or structured
results, and direct resource reads. Tests use the actual initializer callback
with fake DNS and count zero HTTP calls for metadata, loopback, RFC1918, private
IPv6, and private/mixed DNS results. Unset/non-callable/false/nil approvals fail
closed. HTTPX's default resource-reader session does **not** follow redirects;
a real request-pipeline test with canned physical I/O verifies a public redirect
to metadata never causes a second request. Do not enable redirect-following
without validating each destination before I/O.

**Known limitation retained:** `UrlGuard.verify!` resolves before HTTPX makes
its own connection. The documented DNS-rebinding/TOCTOU window remains; this
patch does not pin resolved IPs or claim all SSRF risks are eliminated. Stdio,
SSE, streamable HTTP, OAuth, and their policies are not rewritten.

The app tool-execution controller now converts only its HTTP JSON response:
real attachments become `{type, data, mimeType, filename}` with strict base64
data, arrays/hashes recurse without changing keys/order, and JSON primitives
remain unchanged. Unsupported objects fail rather than invoking arbitrary
`as_json`/IO inspection. The model/LLM loop still receives the real decoded
RubyLLM attachment objects. PNG/audio endpoint regressions exercise the actual
remote tool, `McpServer#execute_tool`, authenticated route, and JSON rendering;
plain/structured/error semantics and the existing argument/tenant boundaries
are retained. No core attachment serializer or global monkey patch is added.

### Task 7 integration-review explicit generation

RubyLLM 2.0 `complete` resumes pending work; assistant-ended and system-only
histories are already `complete?` and otherwise echo supplied messages without
provider generation. MCP prompt asks and sampling are explicit generation
requests. The three files listed above now use public `generate` at that
boundary, without fake user messages, private APIs, core patches, or double
generation for user-ended histories. Prompt asks retain their complete tool
loop, approval pauses, cancellation, and streamed chunks on plain and persisted
chats. Sampling performs one generation with no configured local tools.

`test/lib/ruby_llm_mcp_generation_test.rb` replaces the former sampling
completion-stub fixture with real-loop Faraday-canned provider tests. They
verify actual request counts, generated response model/content, original
history and binary PNG/WAV attachments, tool continuation, approval/resume,
cancellation, and streaming without duplicate chunks. The earlier conversion
assertions are retained there rather than hidden behind a stubbed `complete`.
The inventory remains **11 modified imported files / 109 pristine files**;
this follow-up changes only three already-patched runtime sources. The exact
supported target remains RubyLLM **2.0.0**, not arbitrary 2.x. Earlier Task 8
verification counts are historical; current follow-up evidence is in the app
upgrade runbook. The known URL-policy DNS-rebinding limitation remains unchanged.

## Maintenance and removal

1. Preserve the pristine archive hash above as the comparison base. Fetch and
   verify it outside the repository before reviewing or refreshing the patch.
2. Keep the runtime-file inventory and behavior above current. Keep
   stdio, SSE, and streamable HTTP transports and security checks unchanged.
3. Run the MCP/local-engine compatibility tests without provider credentials,
   alongside the application accounting and migration verification gates.
4. For a future upstream release with RubyLLM 2.0 support, inspect its published
   gemspec, compare every patched boundary, and run those same tests before
   replacing the path dependency. Remove this vendor directory only once the
   upstream release fully replaces the local patch; do not merely loosen the
   version constraint or assume newer 2.x compatibility.
