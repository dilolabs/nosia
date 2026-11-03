# Orbite Compact Premium Chat Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved compact B header with one input/output distribution bar, no Usage table and no hidden accounting information.

**Architecture:** Keep the existing saved-only header, Usage section and localized Turbo replacement root. Render the current counters, a presentation-only total and passive proportional segments on the server; show every kind's exact input/output as ordinary lines. Use header-scoped Orbite CSS, not a new JavaScript, chart, accounting or focus owner.

**Tech Stack:** Actual checkout: Ruby 4.0.7, Rails 8.0.5.1, PostgreSQL, ERB, Turbo/Stimulus, Importmap/Propshaft, Ruby-native Tailwind 4, Minitest/fixtures, local Chromium/Selenium. No installations or upgrades.

---

## Authority and current boundary

- Approved [written specification](../specs/2026-11-02-orbite-compact-premium-chat-header-design.md), user reviewed `25432fc` and answered **“Oui”**; approval metadata committed as `7ff27c11076e1287473ad19b6f29f64cdd7a9e0f`. The user selected compactness, everything visible, simplified B and **one global bar**. Do not reopen these choices or substitute a quota/progress gauge.
- This existing worktree/branch is already selected. Execution mode remains **fresh implementer → independent SPEC → different independent QUALITY**; do not ask again or create another worktree. Parent self-reviews this plan, not a plan-review subagent.
- Prior header implementer `ses_e643d1793ffeLG1fLot1UTUSFd` is PAUSED/no active application command. Do not resume it in parallel with the fresh premium implementer.
- Paused evidence `P=/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/header-controls-20261102-7a9c42/resume-question-1f6d93`: `pause-user-steering-index.json`, `tested-freeze.json`, original request **53/1066** and native **247/84447** success. Those ran HEAD034b256 plus the frozen working source, not this future UI. Full log/PNG acceptance, localization/lint and reviews were unfinished.
- All1099 paused inputs and five D drafts were preserved during the two spec-only commits. Original plan59e59d5 is a child of7ff27c; the following source-audit correction is a plan-only child of59e59d5. Bind actual current HEAD and that exact docs-only ancestry. Bridge the old source map plus the new spec/plan explicitly; never retrofit an old hardcoded-HEAD utility or relabel an old run.
- Preserve the existing18 uncommitted code candidates. The coherent eventual code commit expands to **exact25 paths** below; no partial commit of the old18 and no documentation in that code commit.

## Execution safety

Every shell, including static/git shells, uses this complete preamble and cwd:

```bash
# workdir=/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui
source /tmp/opencode/chat-workspace-env.sh || exit $?
export E=/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq
export EVIDENCE="$E"
export ORBITE_SOURCE_SHA="$(git rev-parse HEAD)"
source "$E/recorder.sh" || exit $?
```

Set `EVIDENCE` to a new exclusive child directory for this task's artifacts after
that preamble. The helper/recorder are read-only. Foreground build/test/browser
groups use tool `timeout=0`, sequential execution and real exit-preserving
`nav_record ... || exit $?`. Expected RED is the only application nonzero allowed
to continue after its actual failure is inspected. Unexpected F/E/S stops.

No dotenv read/copy/dump, development-process inspection/control, provider/MCP/
crawl/embedding calls, worker/job perform/queue drain, install, unsafe unrestricted
suite, DB setup/prepare/migrate/reset or DDL. The Cable transport table/index is
already present and verified: **do not repeat DDL or historical prerequisites**.
Do not rerun old diagnostics, scans or tests merely to reconstruct lost receipts.
The static companion is a separate consented mockup, not application evidence.

### Source-audit corrections before application execution

The first premium checkpoint correctly stopped: the old generated CSS was
195289bytes/SHA256`38ce4d11dbabdb2ab36fef6d495f3dae4fc90a16c6c3d0ea5005930de4720189`,
while the current artifact was195300bytes/SHA256
`83388fdc21e412248416b243229c710ec29d30db68d1f2dd59fb2ef3c923be8c`.
All1099 paused source inputs and the other11504 runtime bindings remained exact.
The artifact's writer/time were not established and no development process was
inspected. Do not restore bytes or silently accept a mismatched old freeze.

A single installed-native Tailwind compilation of the then-current unchanged
application source to an **external** output produced exactly the current CSS;
the repository artifact was never overwritten. Actual receipt:
`/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/premium-parent-cssprobe-20261102-9cd72b/source-only-css-comparison.json`.
This proves current-source reproducibility at that source, not the old artifact's
provenance. After this plan-only correction, require a new source-specific bridge
at the actual new HEAD before accepting the checkpoint. It again writes only an
exclusive external CSS output and must compare equal to the untouched repository
asset, with all11504 other runtime bindings and all current source bytes exact.
If it differs, stop; no automatic asset replacement, rebaseline or retry.

Also, `test/integration/localized_broadcasts_test.rb` explicitly performs Turbo
render jobs. Its full-file addition to this task was overbroad and conflicts
with the unchanged no-job-performance rule. **Do not run or filter that file.**
Withdraw it from this task's final request selection before any test has run;
retain it unchanged. The new premium request tests below instead capture actual
localized synchronous totals and verify no foreign-chat delivery, while the
complete existing rendering/footer/access files remain selected. This is a
safety correction, not selection of a green subset after a test failure. The
final request group now contains14 files. No job-performance exception is granted.

## Exact ownership

### New premium production changes — five existing files

1. `app/views/chats/_header.html.erb`: remove duplicate toolbar account; mark full Usage account.
2. `app/views/chats/_token_totals.html.erb`: retain live root/counters/estimates; replace table with passive bar and labelled kind lines.
3. `app/assets/stylesheets/nosia/orbite_chat.css`: append only the scoped header block below; existing History/reader/dock rules stay exact.
4. `config/locales/en.nosia_chat_workspace.yml`: add the one distribution label.
5. `config/locales/fr.nosia_chat_workspace.yml`: matching French label.

### New/coupled tests

- Create `test/integration/premium_chat_header_test.rb`.
- Create `test/system/premium_chat_header_test.rb`.
- Modify only enumerated presentation contracts in:
  `test/integration/compact_headers_test.rb`,
  `test/integration/chat_message_rendering_test.rb`,
  `test/integration/token_footer_test.rb`,
  `test/system/compact_headers_test.rb`,
  `test/system/chat_workspace_test.rb`,
  `test/system/orbite_history_density_test.rb`.

### Exact combined25-path code commit

```text
app/assets/stylesheets/nosia/orbite_chat.css
app/assets/stylesheets/nosia/orbite_shell.css
app/javascript/controllers/workspace_navigation_controller.js
app/views/application/_orbite_shell.html.erb
app/views/chats/_header.html.erb
app/views/chats/_history_items.html.erb
app/views/chats/_token_totals.html.erb
config/locales/en.nosia_chat_workspace.yml
config/locales/fr.nosia_chat_workspace.yml
test/controllers/chat_workspace_test.rb
test/controllers/dashboards_controller_test.rb
test/controllers/settings_workspace_test.rb
test/controllers/sources_workspace_shell_test.rb
test/controllers/token_usage_workspace_shell_test.rb
test/integration/compact_headers_test.rb
test/integration/orbite_shell_test.rb
test/integration/chat_message_rendering_test.rb
test/integration/token_footer_test.rb
test/integration/premium_chat_header_test.rb
test/support/orbite_browser_checks.rb
test/system/chat_workspace_test.rb
test/system/compact_headers_test.rb
test/system/orbite_workspace_test.rb
test/system/orbite_history_density_test.rb
test/system/premium_chat_header_test.rb
```

Names in this list outside premium ownership are **preserved prior work**, not
new editing permission. All production JS, shell/History partials, shell CSS,
backend, fixtures, dependencies, shared native helpers and dock/new/show/message
markup stay paused bytes. In the density file preserve all six current permanent
units, strict traversal, rail-return regression/sampler and paint helpers; only
the duplicate-account recovery block and `density_header` may change below.
Keep all reader/interception/resize/frame/anchor helpers and their tolerances exact.

Five D drafts remain unchanged/unstaged throughout the code task:
`docs/README.md`, `docs/chat-composer.md`, `docs/chat-workspace.md`,
`docs/compact-headers.md`, `docs/orbite-workspace.md`. Spec and plan are parent-owned.

## Task 0 — Bridge the paused source and audit the new entrypoints

- [ ] Reserve a unique directory under `E`, set it as `EVIDENCE`, and write new external scripts with patch/exclusive output names. No old report/index/utility is overwritten.
- [ ] Verify actual branch/index, the spec/spec-approval/plan/plan-correction-only ancestry above034b256 and all1099 paused input hashes/modes. Include the two new documents in a fresh checkpoint; include the two new test files once created. Reject unexpected tracked/untracked inputs, symlinks/path escapes and any `.env` component.
- [ ] Snapshot the25 candidates and five drafts before edits. Check the actual11505 runtime bindings and101 installed-source bindings from `P/tested-freeze.json` and prior checkpoint;11504 remain strict old bindings, while only the generated CSS uses the parent-approved current-source bridge described above. Reuse unchanged audits, not prerequisite commands. Only generated `app/assets/builds/tailwind.css` may differ after the later authorized production build and must enter the final runtime freeze.
- [ ] Read the exact selected tests/supports, helper/recorder, changed GET/render/broadcast callers and new test listings before boot. Local TokenUsage creation uses the existing test adapter/Cable, not live providers or performed jobs. Audit cached counters and the unchanged energy/fallback computation. Record this bounded delta in a fresh audit; stop on an unsafe caller.
- [ ] Record preserved original artifacts by their actual paths/hashes, especially the pause index, source/runtime maps, question-link amendment and raw failures. An artifact hash check is static preservation, not a replay or acceptance.

Create `candidates.txt` in the new evidence directory using the exact25-path list
above, then create that directory's new `state.py` with this complete tool. It
does not boot Rails, mutate application files, execute SQL or run prerequisites:

```python
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

R = Path('/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui')
P = Path('/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/header-controls-20261102-7a9c42/resume-question-1f6d93')
F = Path(__file__).parent
SPEC = 'docs/superpowers/specs/2026-11-02-orbite-compact-premium-chat-header-design.md'
PLAN = 'docs/superpowers/plans/2026-11-02-orbite-compact-premium-chat-header.md'
NEW = {'test/integration/premium_chat_header_test.rb', 'test/system/premium_chat_header_test.rb'}
LEGACY_UNTRACKED = {'docs/orbite-workspace.md', 'test/system/orbite_history_density_test.rb'}
DOCS = ['docs/README.md', 'docs/chat-composer.md', 'docs/chat-workspace.md', 'docs/compact-headers.md', 'docs/orbite-workspace.md']
MUTABLE = {
    'app/views/chats/_header.html.erb', 'app/views/chats/_token_totals.html.erb',
    'app/assets/stylesheets/nosia/orbite_chat.css',
    'config/locales/en.nosia_chat_workspace.yml', 'config/locales/fr.nosia_chat_workspace.yml',
    'test/integration/compact_headers_test.rb', 'test/integration/chat_message_rendering_test.rb',
    'test/integration/token_footer_test.rb', 'test/system/compact_headers_test.rb',
    'test/system/chat_workspace_test.rb', 'test/system/orbite_history_density_test.rb',
} | NEW
CANDIDATES = (F / 'candidates.txt').read_text().splitlines()
assert len(CANDIDATES) == len(set(CANDIDATES)) == 25
pause = json.loads((P / 'pause-user-steering-index.json').read_text())
old_runtime = json.loads((P / 'tested-freeze.json').read_text())['runtime']
BRIDGE = Path('/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/premium-parent-cssbridge-20261102-a6101e/css-bridge.json')
bridge = json.loads(BRIDGE.read_text())
generated = str(R / 'app/assets/builds/tailwind.css')
assert bridge['verified_equal'] and not bridge['repository_output_modified']
assert bridge['runtime_except_generated_unchanged'] == 11504
runtime_reference = dict(old_runtime)
runtime_reference[generated] = old_runtime[generated] | bridge['compiled']

def git(*args):
    return subprocess.check_output(['git', *args], cwd=R).decode()

def binding(path):
    path = Path(path)
    assert not any(part == '.env' or part.startswith('.env.') for part in path.parts)
    assert path.is_file() and not path.is_symlink(), str(path)
    data = path.read_bytes()
    return {
        'sha256': hashlib.sha256(data).hexdigest(),
        'blob': hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest(),
        'bytes': len(data),
        'mode': oct(stat.S_IMODE(path.stat().st_mode)),
        'gitMode': '100755' if path.stat().st_mode & 0o111 else '100644',
    }

def runtime_binding(name):
    path = Path(name)
    assert not any(part == '.env' or part.startswith('.env.') for part in path.parts)
    resolved = path.resolve(strict=True)
    item = binding(resolved)
    return {key: item[key] for key in ['sha256', 'bytes', 'mode']} | {
        'realPath': str(resolved), 'symlink': os.readlink(path) if path.is_symlink() else None,
    }

def current():
    assert Path.cwd() == R
    assert git('branch', '--show-current').strip() == 'feat/chat-workspace-ui'
    assert not git('diff', '--cached', '--name-only')
    prefixes = ['app', 'test', 'config', 'lib', 'db', 'vendor', 'bin', 'Gemfile',
                'Gemfile.lock', '.ruby-version', '.rubocop.yml', 'AGENTS.md', 'docs']
    names = set(filter(None, git('ls-files', '-z', '--', *prefixes).split('\0')))
    untracked = set(filter(None, git('ls-files', '--others', '--exclude-standard', '-z').split('\0')))
    assert untracked <= LEGACY_UNTRACKED | NEW, untracked
    names |= untracked
    return {'head': git('rev-parse', 'HEAD').strip(),
            'inputs': {name: binding(R / name) for name in sorted(names)},
            'runtime': {name: runtime_binding(name) for name in old_runtime},
            'candidates': {name: binding(R / name) for name in CANDIDATES if (R / name).exists()},
            'runtimeBasis': {'old_freeze': str(P / 'tested-freeze.json'), 'css_bridge': str(BRIDGE),
                             'css_bridge_sha256': hashlib.sha256(BRIDGE.read_bytes()).hexdigest()}}

def method(data, name):
    pattern = rb'^    def ' + re.escape(name.encode()) + rb'(?:\([^\n]*\))?\n.*?^    end$'
    match = re.search(pattern, data, re.M | re.S)
    assert match, name
    return match.group()

def preserved(checkpoint, now):
    assert now['head'] == checkpoint['head']
    assert set(now['inputs']) - set(checkpoint['inputs']) <= NEW
    assert set(checkpoint['inputs']) <= set(now['inputs'])
    for name, item in checkpoint['inputs'].items():
        assert now['inputs'][name]['mode'] == item['mode'], name
        if name not in MUTABLE:
            assert now['inputs'][name] == item, name
    for name, item in old_runtime.items():
        if name != str(R / 'app/assets/builds/tailwind.css'):
            assert now['runtime'][name] == item, name
    css = 'app/assets/stylesheets/nosia/orbite_chat.css'
    assert (R / css).read_bytes().startswith((F / 'before' / css).read_bytes())
    compact = 'test/system/compact_headers_test.rb'
    old = (F / 'before' / compact).read_bytes()
    new = (R / compact).read_bytes()
    for name in ['header_prepare_paused_chat', 'header_reader_anchor',
                 'header_defer_resize_acknowledgment', 'header_resize_sample',
                 'header_hold_reader_frame', 'header_ordering_tail',
                 'header_wait_for_message_animations', 'header_tab_to', 'header_hit', 'header_contrast']:
        assert method(old, name) == method(new, name), name
    density = 'test/system/orbite_history_density_test.rb'
    old = (F / 'before' / density).read_bytes()
    new = (R / density).read_bytes()
    markers = [b'  test "density characterization', b'  test "native design', b'    def density_seed',
               b'    def density_expected', b'    def density_open', b'    def density_characterization', b'    def density_rows']
    def units(data):
        pos = [data.index(marker) for marker in markers]
        return [data[:pos[0]], data[pos[0]:pos[1]], *[data[pos[i]:pos[i+1]] for i in range(2, 6)]]
    assert units(old) == units(new)
    for name in ['density_rows', 'density_tab_to', 'density_rail_return_geometry', 'density_paint_functions']:
        assert method(old, name) == method(new, name), name
    start, end = b'  test "rail opener return', b'  private'
    assert old[old.index(start):old.index(end)] == new[new.index(start):new.index(end)]
    chat = 'test/system/chat_workspace_test.rb'
    expected = (F / 'before' / chat).read_bytes().replace(
        b'section#chat-usage-details tr[data-usage-kind=agent_skill]',
        b'section#chat-usage-details li[data-usage-kind=agent_skill]')
    assert (R / chat).read_bytes() == expected

mode, target = sys.argv[1], Path(sys.argv[2])
now = current()
for name, item in pause['artifacts'].items():
    actual = binding(P / name)
    assert all(actual[key] == item[key] for key in ['sha256', 'bytes', 'mode']), name
if mode == 'checkpoint':
    assert set(git('diff', '--name-only', pause['head'], now['head']).splitlines()) == {SPEC, PLAN}
    assert set(now['inputs']) == set(pause['inputs']) | {SPEC, PLAN}
    for name, item in pause['inputs'].items():
        assert now['inputs'][name] == item, name
    assert bridge['head'] == now['head'] and bridge['inputs'] == now['inputs']
    assert now['runtime'] == runtime_reference
    for name in CANDIDATES + DOCS:
        if (R / name).exists():
            destination = F / 'before' / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open('xb') as output:
                output.write((R / name).read_bytes())
elif mode == 'freeze':
    preserved(json.loads(Path(sys.argv[3]).read_text()), now)
    assert set(now['candidates']) == set(CANDIDATES)
elif mode == 'check':
    assert now == json.loads(target.read_text())
else:
    raise SystemExit('Expected checkpoint, freeze or check')
if mode != 'check':
    with target.open('x') as output:
        json.dump(now, output, indent=2, sort_keys=True)
print(json.dumps({'mode': mode, 'head': now['head'], 'inputs': len(now['inputs']),
                  'runtime': len(now['runtime']), 'candidates': len(now['candidates'])}))
```

Run after the mandatory preamble, with `EVIDENCE` pointing to the new directory:

```bash
nav_record premium-checkpoint python3 "$EVIDENCE/state.py" checkpoint "$EVIDENCE/checkpoint.json" || exit $?
```

Also bind prior map/audit hashes and the101 installed-source receipts. The script
protects all six current density units and the individual strict helpers, rather
than incorrectly treating `density_tab_to` through the mutable `density_header`
as one unchanged block. No Rails build/test/browser starts until this source/
runtime checkpoint and the selected-caller safety audit pass.

## Task 1 — Add request REDs, baseline geometry and native RED

### 1A. New request file

- [ ] Add this complete file. It uses the existing owned fixtures and no provider/job execution.

```ruby
require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_workspace_fixtures"

class PremiumChatHeaderTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable::TestHelper

  setup { sign_in_picker_user }

  %i[en fr].each do |locale|
    test "premium header retains all information without a table in #{locale}" do
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select ".n-chat-toolbar h1.n-chat-title", count: 1
      assert_select ".n-chat-toolbar [data-chat-account-label]", count: 0
      assert_select ".n-chat-header [data-chat-account-label]", text: @second.name, count: 1
      assert_select "section#chat-usage-details[aria-labelledby=chat-usage-summary]", count: 1
      assert_select "#chat-usage-details > h2#chat-usage-summary:not([tabindex])", count: 1
      assert_select ".n-chat-toolbar a[href='#{new_chat_path}']", count: 1
      assert_select ".n-chat-header #workspace-history-trigger, .n-chat-header a[href='#{user_root_path}']", count: 0
      fragment = Nokogiri::HTML.fragment(response.body)
      assert_distribution(fragment, chat: @chat, input: 125, output: 24, locale: locale)
      @chat.token_totals_by_kind.each do |kind, values|
        assert_select fragment, "li[data-usage-kind='#{kind}']" do
          assert_select ".n-chat-token-kind-name", text: I18n.t("nosia.usage.kinds.#{kind}", locale: locale)
          assert_select "[data-usage-input]", text: formatted(values.first, locale)
          assert_select "[data-usage-output]", text: formatted(values.last, locale)
          assert_select "dt", text: I18n.t("nosia.usage.input", locale: locale)
          assert_select "dt", text: I18n.t("nosia.usage.output", locale: locale)
        end
      end
      assert_select "#chat-usage-details [data-estimate-note]", text: I18n.t("nosia.usage.total_fallback_tooltip", locale: locale)
      assert_select "#chat-usage-details [data-chat-impact-estimates]", text: /kWh.*gCO₂e/m
      assert_no_enqueued_jobs only: ChatResponseJob
    end

    { zero: [0, 0], input_only: [17, 0], output_only: [0, 19], large: [1_234_567_890, 987_654_321] }.each do |state, values|
      test "#{locale} premium #{state} summary uses exact cached counts" do
        chat = workspace(:chats, :workspace_first_chat)
        assert_empty chat.token_usages
        chat.update_columns(input_tokens_count: 0, output_tokens_count: 0)
        input, output = values
        if input.positive? || output.positive?
          TokenUsage.create!(account: @first, chat: chat, kind: :completion,
            model_id: "picker-test-model", input_tokens: input, output_tokens: output)
        end
        chat.reload
        before = [ chat.input_tokens_count, chat.output_tokens_count, chat.token_usages.count ]
        fragment = I18n.with_locale(locale) do
          Nokogiri::HTML.fragment(ApplicationController.render(partial: "chats/token_totals", locals: { chat: chat }))
        end
        assert_distribution(fragment, chat: chat, input: input, output: output, locale: locale)
        assert_equal before, [ chat.reload.input_tokens_count, chat.output_tokens_count, chat.token_usages.count ]
        if state == :zero
          assert_select fragment, ".n-chat-token-caption", text: I18n.t("nosia.usage.none", locale: locale)
          assert_select fragment, "li[data-usage-kind]", count: 0
          assert_select fragment, "[data-estimate-note]", text: I18n.t("nosia.usage.total_tooltip", locale: locale)
        end
        assert_no_enqueued_jobs only: ChatResponseJob
      end
    end

    test "#{locale} actual totals replacement updates counts and distribution together" do
      Current.reset
      streams = nil
      foreign = capture_turbo_stream_broadcasts([ chats(:picker_foreign_chat), :token_totals, locale ]) do
        streams = capture_turbo_stream_broadcasts([ @chat, :token_totals, locale ]) do
          TokenUsage.create!(account: @second, chat_id: @chat.id, kind: :agent_skill,
            model_id: "picker-test-model", input_tokens: 2, output_tokens: 3)
        end
      end
      assert_empty foreign
      replacement = streams.find { |stream| stream["target"] == dom_id(@chat, :token_totals) }
      assert replacement
      assert_equal "replace", replacement["action"]
      assert_distribution(replacement.at_css("template"), chat: @chat, input: 127, output: 27, locale: locale)
      assert_select replacement.at_css("template"), "li[data-usage-kind=agent_skill] [data-usage-input]", text: "2"
      assert_select replacement.at_css("template"), "li[data-usage-kind=agent_skill] [data-usage-output]", text: "3"
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  private
    def formatted(value, locale)
      I18n.with_locale(locale) { ApplicationController.helpers.number_with_delimiter(value) }
    end

    def assert_distribution(fragment, chat:, input:, output:, locale:)
      root = "##{dom_id(chat, :token_totals)}"
      assert_select fragment, root, count: 1
      assert_select fragment, "#{root} [data-chat-total-input]", text: formatted(input, locale)
      assert_select fragment, "#{root} [data-chat-total-output]", text: formatted(output, locale)
      assert_select fragment, "#{root} [data-chat-total-tokens]", text: formatted(input + output, locale)
      assert_select fragment, "#{root} [data-chat-token-bar][aria-hidden=true][data-empty='#{(input + output).zero?}']", count: 1
      { input: input, output: output }.each do |part, count|
        selector = "#{root} [data-chat-token-part='#{part}']"
        assert_select fragment, selector, count: count.positive? ? 1 : 0
        if count.positive?
          assert_equal "flex-grow: #{count}", fragment.at_css(selector)["style"]
        end
      end
      assert_select fragment, "#{root} table, #{root} details, #{root} summary, #{root} [hidden], #{root} [role=progressbar], #{root} canvas", count: 0
      assert_select fragment, "#{root} [data-chat-token-bar] [tabindex], #{root} [data-chat-token-bar] a, #{root} [data-chat-token-bar] button", count: 0
      assert_select fragment, "#{root} [data-estimate-note]", count: 1
    end
end
```

- [ ] Run the two meaningful missing-design request cases, inspect full raw and require missing bar/removed-duplicate/table assertions, zero errors/skips. Old header RED/GREEN is not rerun.

```bash
if nav_record premium-request-red rails_test test test/integration/premium_chat_header_test.rb -i /premium_header_retains_all_information/; then
  exit 125
else
  result=$?
  test "$result" -eq 1 || exit "$result"
fi
```

### 1B. New native characterization and design test file

- [ ] Add the complete native file below before production. `PREMIUM_HEADER_PHASE` labels evidence only; it never changes an assertion's expected behavior. No new shared helper change.

```ruby
require "application_system_test_case"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/chat_workspace_browser_checks"

class PremiumChatHeaderSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include ChatWorkspaceBrowserChecks
  include Turbo::Broadcastable::TestHelper

  setup do
    @original_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(*@original_size)
  end

  test "records real header density without changing application geometry" do
    premium_contexts do |locale, width, height, dark|
      premium_top
      sample = premium_geometry
      phase = ENV.fetch("PREMIUM_HEADER_PHASE", "candidate")
      orbite_record("premium-density-#{phase}-#{locale}-#{width}x#{height}-#{dark}", sample, screenshot: true)
      assert_equal [125, 24], sample.fetch("counts")
      assert_equal @second.name, sample.fetch("account")
      assert sample.fetch("insideReader")
      refute_includes %w[fixed sticky], sample.fetch("position")
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "single distribution replaces the table without hiding values" do
    premium_contexts do |locale, width, height, dark|
      assert_selector "#chat-usage-details [data-chat-token-bar][aria-hidden=true]", count: 1
      assert_no_selector "#chat-usage-details table, #chat-usage-details details, #chat-usage-details [role=progressbar], .n-chat-toolbar [data-chat-account-label]", visible: :all
      assert_selector ".n-chat-header [data-chat-account-label]", text: @second.name, exact_text: true, count: 1
      assert_selector "[data-chat-total-tokens]", text: "149", exact_text: true
      %w[completion embedding].each do |kind|
        assert_selector "li[data-usage-kind='#{kind}'] [data-usage-input]"
        assert_selector "li[data-usage-kind='#{kind}'] [data-usage-output]"
      end
      assert_selector "[data-estimate-note]", text: I18n.t("nosia.usage.total_fallback_tooltip", locale: locale)
      premium_top
      bar = page.evaluate_script(<<~JS)
        (() => {
          const bar = document.querySelector('[data-chat-token-bar]'), style = getComputedStyle(bar)
          const parts = [...bar.querySelectorAll('[data-chat-token-part]')]
          return { width: bar.getBoundingClientRect().width, gap: parseFloat(style.columnGap),
            parts: parts.map(part => ({ name: part.dataset.chatTokenPart, width: part.getBoundingClientRect().width })),
            focusables: bar.querySelectorAll('a,button,input,select,summary,[tabindex]').length }
        })()
      JS
      available = bar.fetch("width") - bar.fetch("gap")
      assert_in_delta available * 125.0 / 149, bar.fetch("parts").first.fetch("width"), 1, bar.to_json
      assert_in_delta available * 24.0 / 149, bar.fetch("parts").last.fetch("width"), 1, bar.to_json
      assert_equal 0, bar.fetch("focusables")
      chat_contrast "#chat-usage-summary"
      chat_contrast "[data-chat-account-label]"
      chat_contrast "[data-chat-total-input]"
      chat_contrast "[data-chat-total-output]"
      chat_contrast "[data-estimate-note]"
      %w[input output].each { |part| premium_segment_contrast(part) }
      orbite_tab_to(".n-chat-toolbar a[href='#{new_chat_path}']")
      chat_contrast ".n-chat-toolbar a[href='#{new_chat_path}']", minimum: 3, outline: true
      bounds = orbite_assert_reachable(".n-chat-toolbar a[href='#{new_chat_path}']")
      assert_operator bounds.fetch("width"), :>=, 44
      assert_operator bounds.fetch("height"), :>=, 44
      assert page.evaluate_script("document.scrollingElement.scrollWidth <= innerWidth")
      assert_no_enqueued_jobs only: ChatResponseJob
      orbite_record("premium-bar-#{locale}-#{width}x#{height}-#{dark}", bar, screenshot: true)
      if locale == "fr" && width == 812 && dark
        page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [{ name: "prefers-reduced-motion", value: "reduce" }])
        assert page.evaluate_script("[...document.querySelectorAll('[data-chat-token-bar], [data-chat-token-part]')].every(node => getComputedStyle(node).animationName === 'none' && getComputedStyle(node).transitionDuration.split(',').every(value => parseFloat(value) === 0))")
      end
    end
  end

  { zero: [0, 0], input_only: [17, 0], output_only: [0, 19], large: [1_234_567_890, 987_654_321] }.each do |state, values|
    test "#{state} bar and long account keep exact visible information" do
      chat = workspace(:chats, :workspace_first_chat)
      assert_empty chat.token_usages
      chat.update_columns(input_tokens_count: 0, output_tokens_count: 0)
      @first.update_columns(name: "CompteDeRecherche" * 12)
      input, output = values
      if input.positive? || output.positive?
        TokenUsage.create!(account: @first, chat: chat, kind: :completion,
          model_id: "picker-test-model", input_tokens: input, output_tokens: output)
      end
      %w[en fr].product([[375, 812], [1400, 1000]], [false, true]).each do |locale, (width, height), dark|
        orbite_viewport(width, height)
        orbite_select_language(locale.upcase)
        visit chat_path(chat)
        assert_selector "lexxy-editor[connected]"
        orbite_theme(dark)
        premium_top
        assert_selector ".n-chat-header [data-chat-account-label]", text: @first.name, exact_text: true, count: 1
        { input: input, output: output, tokens: input + output }.each do |name, value|
          expected = I18n.with_locale(locale) { ApplicationController.helpers.number_with_delimiter(value) }
          assert_selector "[data-chat-total-#{name}]", text: expected, exact_text: true
        end
        assert_selector "[data-chat-token-bar][data-empty='#{(input + output).zero?}']"
        assert_selector "[data-chat-token-part]", count: values.count(&:positive?)
        assert_selector "[data-estimate-note]", count: 1
        assert_no_selector "#chat-usage-details table, #chat-usage-details details", visible: :all
        sample = page.evaluate_script(<<~JS)
          (() => {
            const node = document.querySelector('[data-chat-account-label]'), range = document.createRange()
            range.selectNodeContents(node)
            const box = node.getBoundingClientRect(), style = getComputedStyle(node)
            const bar = document.querySelector('[data-chat-token-bar]'), barStyle = getComputedStyle(bar)
            return { box: box.toJSON(), whiteSpace: style.whiteSpace, textOverflow: style.textOverflow,
              fits: node.scrollWidth <= node.clientWidth && [...range.getClientRects()].every(line => line.left >= box.left - 1 && line.right <= box.right + 1 && line.top >= box.top - 1 && line.bottom <= box.bottom + 1),
              pageWidth: document.scrollingElement.scrollWidth, viewportWidth: innerWidth,
              barWidth: bar.getBoundingClientRect().width, gap: parseFloat(barStyle.columnGap),
              parts: [...bar.querySelectorAll('[data-chat-token-part]')].map(part => ({ name: part.dataset.chatTokenPart, width: part.getBoundingClientRect().width })) }
          })()
        JS
        refute_equal "nowrap", sample.fetch("whiteSpace")
        refute_equal "ellipsis", sample.fetch("textOverflow")
        assert sample.fetch("fits"), sample.to_json
        assert_operator sample.fetch("pageWidth"), :<=, sample.fetch("viewportWidth"), sample.to_json
        parts = sample.fetch("parts")
        if input + output > 0
          available = sample.fetch("barWidth") - [parts.size - 1, 0].max * sample.fetch("gap")
          parts.each do |part|
            count = part.fetch("name") == "input" ? input : output
            assert_in_delta available * count.fdiv(input + output), part.fetch("width"), 1, sample.to_json
          end
        else
          assert_empty parts
        end
        orbite_record("premium-#{state}-#{locale}-#{width}-#{dark}", sample, screenshot: true)
      end
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "actual localized replacement preserves the draft and updates the passive bar" do
    %w[en fr].each do |locale|
      orbite_viewport(375, 812)
      orbite_select_language(locale.upcase)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      find("lexxy-editor .lexxy-editor__content").send_keys("Keep this native premium draft")
      page.execute_script("window.premiumDraft = document.querySelector('lexxy-editor'); window.premiumFocus = document.activeElement")
      before = @chat.reload
      input, output = before.input_tokens_count + 2, before.output_tokens_count + 3
      kind_output = before.token_totals_by_kind.fetch("agent_skill", [0, 0]).last + 3
      Current.reset
      streams = capture_turbo_stream_broadcasts([ @chat, :token_totals, locale ]) do
        TokenUsage.create!(account: @second, chat_id: @chat.id, kind: :agent_skill,
          model_id: "picker-test-model", input_tokens: 2, output_tokens: 3)
      end
      replacement = streams.find { |stream| stream["target"] == ActionView::RecordIdentifier.dom_id(@chat, :token_totals) }
      assert replacement
      assert_equal "replace", replacement["action"]
      page.execute_script("Turbo.renderStreamMessage(arguments[0])", replacement.to_html)
      { input: input, output: output, tokens: input + output }.each do |name, value|
        expected = I18n.with_locale(locale) { ApplicationController.helpers.number_with_delimiter(value) }
        assert_selector "[data-chat-total-#{name}]", text: expected, exact_text: true, visible: :all
      end
      expected_kind = I18n.with_locale(locale) { ApplicationController.helpers.number_with_delimiter(kind_output) }
      assert_selector "li[data-usage-kind=agent_skill] [data-usage-output]", text: expected_kind, exact_text: true, visible: :all
      assert_equal input.to_f, page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('[data-chat-token-part=input]')).flexGrow)")
      assert_equal output.to_f, page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('[data-chat-token-part=output]')).flexGrow)")
      assert page.evaluate_script("window.premiumDraft === document.querySelector('lexxy-editor') && window.premiumFocus === document.activeElement")
      assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this native premium draft"
      orbite_record("premium-live-#{locale}", { target: replacement["target"], payload: replacement.to_html }, screenshot: true)
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  private
    def premium_contexts
      %w[en fr].product([[375, 812], [768, 1024], [1400, 1000], [812, 375]], [false, true]).each do |locale, (width, height), dark|
        orbite_viewport(width, height)
        orbite_select_language(locale.upcase)
        visit chat_path(@chat)
        assert_selector "lexxy-editor[connected]"
        page.evaluate_async_script(<<~JS)
          const done = arguments[arguments.length - 1]
          Promise.all(document.getAnimations().filter(animation => Number.isFinite(animation.effect.getComputedTiming().endTime))
            .map(animation => animation.finished.catch(() => {}))).then(done)
        JS
        orbite_theme(dark)
        yield locale, width, height, dark
      end
    end

    def settle_workspace_layout
      orbite_settle
    end

    def premium_top
      page.execute_script(<<~JS)
        const reader = document.querySelector('[data-application-scroll]')
        reader.scrollTop = 0
        reader.dispatchEvent(new Event('scroll'))
      JS
      orbite_settle
    end

    def premium_geometry
      page.evaluate_script(<<~JS, @chat.id)
        (() => {
          const header = document.querySelector('.n-chat-header'), reader = document.querySelector('[data-application-scroll]')
          const kinds = [...document.querySelectorAll('#chat-usage-details [data-usage-kind]')].map(row => ({
            kind: row.dataset.usageKind,
            values: [...row.querySelectorAll('td,[data-usage-input],[data-usage-output]')].map(node => node.textContent.trim())
          }))
          return { chat: arguments[0], account: document.querySelector('#chat-usage-details > p').textContent.trim(), kinds,
            counts: ['input','output'].map(part => Number(document.querySelector(`[data-chat-total-${part}]`).textContent.replace(/[^0-9]/g, ''))),
            headerHeight: header.getBoundingClientRect().height, position: getComputedStyle(header).position,
            insideReader: reader.contains(header), reader: reader.getBoundingClientRect().toJSON(),
            transcriptTop: document.querySelector('.n-chat-transcript').getBoundingClientRect().top,
            viewport: [innerWidth, innerHeight], dockTop: document.querySelector('.n-chat-dock').getBoundingClientRect().top }
        })()
      JS
    end

    def premium_segment_contrast(part)
      node = find("[data-chat-token-part='#{part}']")
      chat_scroll_to(node)
      sample = page.evaluate_script(<<~JS, node)
        (() => {
          const node = arguments[0], band = node.closest('#chat-usage-details')
          const parse = color => {
            const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
            const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
            if (!CSS.supports('color', color)) throw new Error(`Unparsed segment color ${color}`)
            context.fillStyle = color; context.fillRect(0, 0, 1, 1)
            return [...context.getImageData(0, 0, 1, 1).data].map(value => value / 255)
          }
          const foreground = parse(getComputedStyle(node).backgroundColor), background = parse(getComputedStyle(band).backgroundColor)
          if (foreground[3] !== 1 || background[3] !== 1) throw new Error('Segment sampling requires opaque fills')
          for (let element = node; element; element = element.parentElement) {
            const style = getComputedStyle(element)
            if (style.backgroundImage !== 'none' || Number(style.opacity) !== 1 || style.filter !== 'none' || style.backdropFilter !== 'none' || style.mixBlendMode !== 'normal') throw new Error('Unmeasured segment paint effect')
          }
          const luminance = rgba => rgba.slice(0,3).map(value => value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4)
            .reduce((sum,value,index) => sum + value * [.2126,.7152,.0722][index],0)
          const a = luminance(foreground), b = luminance(background)
          return { foreground, background, ratio: (Math.max(a,b)+.05)/(Math.min(a,b)+.05),
            marker: getComputedStyle(node, '::after').borderTopStyle }
        })()
      JS
      assert_operator sample.fetch("ratio"), :>=, 3, sample.to_json
      assert_equal "dashed", sample.fetch("marker") if part == "output"
      orbite_record("premium-segment-#{part}", sample)
    end
end
```

The segment check measures the opaque base fills and verifies the non-color
marker; inspect the actual patterned originals separately, not as a claim that
every marker pixel was sampled. No existing contrast/focus helper is weakened.

- [ ] Run the characterization once on the current real header before edits. Store its original16 contexts, raw JSONL and screenshots as the new comparison baseline; it is not RED and not a recreated historical baseline.

```bash
export PREMIUM_HEADER_PHASE=before
nav_record premium-density-before browser_test test/system/premium_chat_header_test.rb -i /records_real_header_density/ || exit $?
unset PREMIUM_HEADER_PHASE
```

- [ ] Run the missing-bar native test once before production; require the expected absence assertion, not a boot/fixture failure.

```bash
if nav_record premium-native-red browser_test test/system/premium_chat_header_test.rb -i /single_distribution_replaces/; then
  exit 125
else
  result=$?
  test "$result" -eq 1 || exit "$result"
fi
```

## Task 2 — Minimal production cutover after meaningful RED

### 2A. Header

- [ ] Replace only `app/views/chats/_header.html.erb` with:

```erb
<header class="n-chat-header">
  <% if chat.persisted? %>
    <div class="n-chat-toolbar">
      <div class="n-chat-heading min-w-0">
        <h1 class="n-chat-title"><%= chat_workspace_title(chat, titles: titles) %></h1>
      </div>
      <div class="n-workspace-actions">
        <%= link_to t("nosia.chat_workspace.new_chat"), new_chat_path, class: "n-workspace-button" %>
      </div>
    </div>
    <section id="chat-usage-details" class="n-chat-usage" aria-labelledby="chat-usage-summary">
      <h2 id="chat-usage-summary" class="n-chat-usage-title"><%= t("nosia.chat_workspace.usage_details") %></h2>
      <p class="n-workspace-help n-chat-usage-account" data-chat-account-label><%= chat.account.name %></p>
      <%= render "chats/token_totals", chat: chat %>
    </section>
  <% end %>
</header>
```

### 2B. Live totals markup, unchanged data sources

- [ ] Replace only `app/views/chats/_token_totals.html.erb` with:

```erb
<%# Live token totals for a chat, refreshed by chat-scoped TokenUsage broadcasts. %>
<%
  totals = chat.token_totals_by_kind
  usages = chat.token_usages.to_a
  input_tokens = chat.input_tokens_count
  output_tokens = chat.output_tokens_count
  total_tokens = input_tokens + output_tokens
%>
<%= tag.div id: dom_id(chat, :token_totals), class: "n-chat-token-layout" do %>
  <div class="n-chat-token-breakdown">
    <div class="n-chat-token-summary">
      <dl class="n-chat-values">
        <div><dt><span class="n-chat-token-key" aria-hidden="true"></span><%= t("nosia.usage.input") %></dt> <dd data-chat-total-input><%= number_with_delimiter(input_tokens) %></dd></div>
        <div><dt><span class="n-chat-token-key n-chat-token-key--output" aria-hidden="true"></span><%= t("nosia.usage.output") %></dt> <dd data-chat-total-output><%= number_with_delimiter(output_tokens) %></dd></div>
      </dl>
      <p class="n-workspace-help n-chat-token-total"><%= t("nosia.usage.total") %> <strong data-chat-total-tokens><%= number_with_delimiter(total_tokens) %></strong> <%= t("nosia.usage.token_unit", count: total_tokens) %></p>
    </div>
    <%= tag.div class: "n-chat-token-bar", aria: { hidden: true }, data: { chat_token_bar: true, empty: total_tokens.zero? } do %>
      <% if input_tokens.positive? %>
        <%= tag.span class: "n-chat-token-segment n-chat-token-segment--input", style: "flex-grow: #{input_tokens}", data: { chat_token_part: "input" } %>
      <% end %>
      <% if output_tokens.positive? %>
        <%= tag.span class: "n-chat-token-segment n-chat-token-segment--output", style: "flex-grow: #{output_tokens}", data: { chat_token_part: "output" } %>
      <% end %>
    <% end %>
    <p class="n-workspace-help n-chat-token-caption"><%= t(total_tokens.zero? ? "nosia.usage.none" : "nosia.chat_workspace.token_distribution") %></p>
    <% if totals.any? %>
      <p class="n-workspace-help n-chat-token-kind-heading"><%= t("nosia.usage.per_kind") %></p>
      <ul class="n-chat-token-kinds" aria-label="<%= t("nosia.usage.per_kind") %>">
        <% totals.each do |kind, sums| %>
          <li data-usage-kind="<%= kind %>">
            <span class="n-chat-token-kind-name"><%= t("nosia.usage.kinds.#{kind}") %></span>
            <dl class="n-chat-token-kind-values">
              <div><dt><%= t("nosia.usage.input") %></dt> <dd data-usage-input><%= number_with_delimiter(sums[0]) %></dd></div>
              <div><dt><%= t("nosia.usage.output") %></dt> <dd data-usage-output><%= number_with_delimiter(sums[1]) %></dd></div>
            </dl>
          </li>
        <% end %>
      </ul>
    <% end %>
  </div>
  <div class="n-chat-token-impact">
    <p class="n-workspace-help" data-chat-impact-estimates>
      <%= t("nosia.chat_workspace.estimates") %>:
      <%= number_with_precision(usages.sum(&:energy_kwh), precision: 6) %> kWh ·
      <%= number_with_precision(usages.sum(&:co2e_g), precision: 2) %> gCO₂e
    </p>
    <p class="n-workspace-help" data-estimate-note><%= t(usages.any?(&:used_fallback?) ? "nosia.usage.total_fallback_tooltip" : "nosia.usage.total_tooltip") %></p>
  </div>
<% end %>
```

Positive counts are flex weights, not widths against a fictitious maximum. Zero
segments are absent; no division is needed, including the all-zero case. Do not
alter counters, grouping, callbacks, energy precision or fallback logic. All
interpolated style values are existing integer counters, not account/user text.

### 2C. Localized label

- [ ] Add exactly this key alongside `usage_details` in each existing locale file:

```yaml
# config/locales/en.nosia_chat_workspace.yml, under en.nosia.chat_workspace
token_distribution: Token distribution for this conversation
```

```yaml
# config/locales/fr.nosia_chat_workspace.yml, under fr.nosia.chat_workspace
token_distribution: Répartition des jetons de cette conversation
```

Indent consistently with neighboring keys. Reuse `nosia.usage.total`,
`token_unit`, `none`, `per_kind`, input/output and kind labels; no copy rewrite.

### 2D. Header-only styling

- [ ] Append this block to `app/assets/stylesheets/nosia/orbite_chat.css`; do not replace earlier History/reader/dock/media rules.

```css
/* Compact saved-chat context; accounting remains server-rendered and visible. */
.n-orbite-shell .n-chat-header .n-chat-toolbar { align-items: center; flex-wrap: nowrap; gap: .75rem; margin-block-end: .625rem; }
.n-orbite-shell .n-chat-header .n-chat-heading { flex: 1 1 0; min-width: 0; }
.n-orbite-shell .n-chat-header .n-workspace-actions { flex: 0 1 auto; max-inline-size: 65%; }
.n-orbite-shell .n-chat-header .n-workspace-button { min-width: 44px; min-height: 44px; max-inline-size: 100%; white-space: normal; overflow-wrap: anywhere; }
.n-orbite-shell .n-chat-usage { --chat-token-output: #6c8364; display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); align-items: baseline; gap: .5rem 1rem; margin-block-start: 0; padding: .625rem .875rem .75rem; background: var(--orbite-bubble); border-radius: .625rem; }
.dark .n-orbite-shell .n-chat-usage { --chat-token-output: #91ab82; }
.n-orbite-shell .n-chat-usage-account { text-align: end; font-size: .75rem; overflow-wrap: anywhere; white-space: normal; }
.n-orbite-shell .n-chat-token-layout { grid-column: 1 / -1; display: grid; grid-template-columns: minmax(0, 1.35fr) minmax(0, 1fr); align-items: start; gap: 1.5rem; min-width: 0; }
.n-orbite-shell .n-chat-token-summary { display: flex; flex-wrap: wrap; align-items: baseline; justify-content: space-between; gap: .25rem 1rem; }
.n-orbite-shell .n-chat-token-summary .n-chat-values { gap: .375rem 1.25rem; margin: 0; }
.n-orbite-shell .n-chat-token-summary .n-chat-values > div { display: flex; align-items: baseline; gap: .375rem; }
.n-orbite-shell .n-chat-token-summary dt { display: inline-flex; align-items: center; gap: .375rem; color: var(--orbite-muted); }
.n-orbite-shell .n-chat-token-summary dd { font-size: 1rem; }
.n-orbite-shell .n-chat-token-total { font-size: .75rem; margin: 0; font-variant-numeric: tabular-nums; }
.n-orbite-shell .n-chat-token-total strong { color: var(--orbite-text); font-weight: 600; }
.n-orbite-shell .n-chat-token-key { display: inline-block; width: .5rem; height: .5rem; border-radius: 2px; background: var(--orbite-accent); }
.n-orbite-shell .n-chat-token-key--output { background: var(--chat-token-output); outline: 1px dashed var(--orbite-text); outline-offset: -1px; }
.n-orbite-shell .n-chat-token-bar { display: flex; gap: 3px; height: .5rem; margin-block: .5rem .25rem; border-radius: .5rem; overflow: hidden; }
.n-orbite-shell .n-chat-token-bar[data-empty=true] { background: var(--orbite-line); }
.n-orbite-shell .n-chat-token-segment { position: relative; display: block; flex-basis: 0; min-width: 0; height: 100%; background: var(--orbite-accent); }
.n-orbite-shell .n-chat-token-segment--output { background: var(--chat-token-output); }
.n-orbite-shell .n-chat-token-segment--output::after { content: ""; position: absolute; inset-inline: 1px; top: 50%; border-top: 1px dashed var(--orbite-bubble); }
.n-orbite-shell .n-chat-token-caption, .n-orbite-shell .n-chat-token-kind-heading { font-size: .75rem; line-height: 1.5; margin: 0 0 .375rem; }
.n-orbite-shell .n-chat-token-kinds { display: flex; flex-direction: column; gap: .25rem; list-style: none; padding: 0; margin: 0; min-width: 0; }
.n-orbite-shell .n-chat-token-kinds > li { display: flex; flex-wrap: wrap; align-items: baseline; gap: .25rem .75rem; min-width: 0; font-size: .875rem; overflow-wrap: anywhere; }
.n-orbite-shell .n-chat-token-kind-name { color: var(--orbite-text); }
.n-orbite-shell .n-chat-token-kind-values { display: flex; flex-wrap: wrap; gap: .25rem .75rem; margin: 0; }
.n-orbite-shell .n-chat-token-kind-values > div { display: flex; flex-wrap: wrap; align-items: baseline; gap: .25rem; }
.n-orbite-shell .n-chat-token-kind-values dt { color: var(--orbite-muted); font-size: .75rem; }
.n-orbite-shell .n-chat-token-kind-values dd { color: var(--orbite-text); font-variant-numeric: tabular-nums; }
.n-orbite-shell .n-chat-token-impact .n-workspace-help { font-size: .75rem; line-height: 1.65; margin: 0; }
.n-orbite-shell .n-chat-token-impact [data-estimate-note] { margin-block-start: .375rem; }
@media (max-width: 767px) {
  .n-orbite-shell .n-chat-usage { grid-template-columns: minmax(0, 1fr); gap: .25rem; padding: .625rem .75rem .75rem; }
  .n-orbite-shell .n-chat-usage-account { text-align: start; }
  .n-orbite-shell .n-chat-token-layout { grid-template-columns: minmax(0, 1fr); gap: .75rem; margin-block-start: .375rem; }
}
```

There is no gradient/transition, fixed band height or new overflow owner. Each
kind has its own ordinary line so a genuinely new kind still produces real
header growth; preserve the existing growth/ResizeObserver tests rather than
removing their positive-growth assertions. Counts/labels retain existing readable
sizes. If a measured layout/contrast failure appears, stop and diagnose within
scope; do not adjust unrelated CSS, test tolerances or reader physics.

## Task 3 — Atomic migration of superseded presentation tests

The following are the complete authorized changes. Preserve all unmentioned
assertions, numeric values, fixture content, genuine keys, event boundaries,
reader oracles, helper bodies and original failure receipts.

### 3A. Request migrations

- [ ] In `test/integration/compact_headers_test.rb`, replace the three caption/column/row assertions inside the saved Usage test with:

```ruby
        assert_select ".n-chat-token-kind-heading", text: I18n.t("nosia.usage.per_kind", locale: locale)
        assert_select "ul.n-chat-token-kinds > li[data-usage-kind]", minimum: 1
        assert_select "table, caption, thead, tbody", count: 0
```

Replace its toolbar account assertion with:

```ruby
    assert_select ".n-chat-toolbar [data-chat-account-label]", count: 0
    assert_select ".n-chat-header [data-chat-account-label]", text: @second.name, count: 1
```

- [ ] In `test/integration/chat_message_rendering_test.rb`, replace the whole background totals table assertion block (currently149–162) with:

```ruby
    assert_select fragment, ".n-chat-token-kind-heading", text: I18n.t("nosia.usage.per_kind")
    assert_select fragment, "table", count: 0
    @chat.token_totals_by_kind.each do |kind, sums|
      assert_select fragment, "li[data-usage-kind='#{kind}']", count: 1 do
        assert_select ".n-chat-token-kind-name", text: I18n.t("nosia.usage.kinds.#{kind}")
        assert_select "[data-usage-input]", text: ApplicationController.helpers.number_with_delimiter(sums[0])
        assert_select "[data-usage-output]", text: ApplicationController.helpers.number_with_delimiter(sums[1])
      end
    end
```

Keep its Current-reset/background counters/energy/fallback assertions. Replace
only the localized live replacement's final `caption` selector with
`#chat-usage-details .n-chat-token-kind-heading`, keeping its exact locale text.

- [ ] In `test/integration/token_footer_test.rb`, migrate its two chat-total caption selectors to `.n-chat-token-kind-heading`, retaining exact texts. Replace the three-column assertion with `assert_select fragment, "ul.n-chat-token-kinds", count: 1` and `assert_select fragment, "table", count: 0`. Replace only `assert_usage_row` with:

```ruby
    def assert_usage_row(fragment, kind:, input:, output:, locale: :en)
      assert_select fragment, "li[data-usage-kind='#{kind}']", count: 1 do
        assert_select ".n-chat-token-kind-name", text: I18n.t("nosia.usage.kinds.#{kind}", locale: locale)
        assert_select "dt", text: I18n.t("nosia.usage.input", locale: locale)
        assert_select "dt", text: I18n.t("nosia.usage.output", locale: locale)
        assert_select "[data-usage-input]", text: input
        assert_select "[data-usage-output]", text: output
      end
    end
```

Its shared two-value `assert_token_values` and **all message token-footer tests**
stay unchanged. The main totals dl deliberately still has exactly two entries.

### 3B. Existing native selector migrations

- [ ] In `test/system/compact_headers_test.rb`, make only these targeted replacements:

```text
"caption", text: I18n.t("nosia.usage.per_kind")
  → ".n-chat-token-kind-heading", text: I18n.t("nosia.usage.per_kind")
"tr[data-usage-kind='#{kind}'] th[scope=row]"
  → "li[data-usage-kind='#{kind}'] .n-chat-token-kind-name"
"#chat-usage-details table"
  → "#chat-usage-details ul.n-chat-token-kinds"
"section#chat-usage-details tr[data-usage-kind=agent_skill]"
  → "section#chat-usage-details li[data-usage-kind=agent_skill]"
```

Do not change the header-height/growth, real broadcasts, native draft, ResizeObserver,
genuine Latest, held-frame and one-key pending-resize scenarios/helpers.

- [ ] Replace only `header_context` with this version; it retires duplicate clipped-account assertions, not full account readability or native recovery:

```ruby
    def header_context(index)
      assert_no_selector ".n-header-details, [data-header-details]", visible: :all
      if page.has_selector?("#chat-usage-details", wait: 0)
        assert_selector "section#chat-usage-details > h2#chat-usage-summary:not([tabindex])"
        assert_no_selector "#chat-usage-details summary, #chat-usage-details[open], .n-chat-toolbar [data-chat-account-label]", visible: :all
        assert_selector ".n-chat-header [data-chat-account-label]", text: @second.name, exact_text: true, count: 1
        assert_header_widths
        header_tab_to(".n-chat-toolbar a[href='#{new_chat_path}']")
        sample = page.evaluate_script(<<~JS)
          (() => {
            const full = document.querySelector('#chat-usage-details > p[data-chat-account-label]')
            const usage = document.querySelector('#chat-usage-details'), actions = document.querySelector('.n-chat-toolbar > .n-workspace-actions')
            const range = document.createRange(); range.selectNodeContents(full)
            const rect = full.getBoundingClientRect(), style = getComputedStyle(full)
            return {
              fullAccount: { text: full.textContent, geometry: rect.toJSON(), whiteSpace: style.whiteSpace,
                textOverflow: style.textOverflow, fits: full.scrollWidth <= full.clientWidth && [...range.getClientRects()].every(line => line.left >= rect.left - 1 && line.right <= rect.right + 1 && line.top >= rect.top - 1 && line.bottom <= rect.bottom + 1) },
              accountLabels: document.querySelectorAll('.n-chat-header [data-chat-account-label]').length,
              ownRow: !actions.contains(usage) && usage.getBoundingClientRect().top >= actions.getBoundingClientRect().bottom }
          })()
        JS
        header_record("matrix-saved-account-usage-#{index}", header_matrix_geometry.merge(sample), screenshot: true)
        assert_equal 1, sample.fetch("accountLabels"), sample.to_json
        assert_operator sample.fetch("fullAccount").fetch("geometry").fetch("left"), :>=, 0, sample.to_json
        assert_operator sample.fetch("fullAccount").fetch("geometry").fetch("right"), :<=, page.evaluate_script("innerWidth"), sample.to_json
        refute_equal "nowrap", sample.fetch("fullAccount").fetch("whiteSpace"), sample.to_json
        refute_equal "ellipsis", sample.fetch("fullAccount").fetch("textOverflow"), sample.to_json
        assert sample.fetch("fullAccount").fetch("fits"), sample.to_json
        assert sample.fetch("ownRow"), sample.to_json
      elsif page.has_selector?(".n-workspace-context .n-workspace-trail a", wait: 0)
        href = URI(find(".n-workspace-context .n-workspace-trail a", match: :first)["href"]).request_uri
        header_tab_to(".n-workspace-context .n-workspace-trail a[href='#{href}']")
        assert_header_widths
        header_record("matrix-inline-context-#{index}", header_matrix_geometry, screenshot: true)
      end
      header_top
    end
```

- [ ] In `test/system/chat_workspace_test.rb`, replace only its actual new-kind growth selector `section#chat-usage-details tr[data-usage-kind=agent_skill]` with the equivalent `li` selector. Keep strict `after_height > before_height`, anchor/following/focus/draft and all other logic exact.
- [ ] In `test/system/orbite_history_density_test.rb`, replace the saved-header account selector with `#chat-usage-details > p[data-chat-account-label]`; change `assert_equal 2, header.fetch("previews").size` to1. Change only the `previews:` array in `density_header` to `['.n-chat-header .n-chat-heading h1'].map(sample)`. Its full question/account `reading:` array and all glyph-fit/native traversal/account recovery assertions remain unchanged. Keep all six current permanent units, row fixtures/semantics, 44px/focus/containment, rail regression and strict samplers exact. The sampler delta is authorized and must be declared, not hidden inside an unchanged-unit claim.

## Task 4 — Focused GREEN, frozen final groups and exact code commit

- [ ] Read actual changed sources/tests before runtime. Build once, then run focused GREEN in order. Any unexpected failure stops; do not run later groups or stage.

```bash
nav_record premium-build rails_test tailwindcss:build || exit $?
nav_record premium-request-green rails_test test test/integration/premium_chat_header_test.rb test/integration/compact_headers_test.rb test/integration/chat_message_rendering_test.rb test/integration/token_footer_test.rb || exit $?
nav_record premium-native-green browser_test test/system/premium_chat_header_test.rb -i /single_distribution_replaces/ || exit $?
nav_record premium-reader-growth browser_test test/system/compact_headers_test.rb test/system/chat_workspace_test.rb -i '/native_reader_.*_navigation_crosses|resize_alone_preserves|visible_Usage_growth|paused_paragraph_survives_compact_header|visible_Usage_and_native_History/' || exit $?
```

- [ ] Create the final current source/runtime/generated-CSS freeze **after** build and before final groups. The two new documents remain frozen, five D drafts and every nonowned byte/mode unchanged. Bind the25 candidate blobs/modes, new tests, actual current HEAD and selection audit. Do not label a future code commit as executed.

```bash
nav_record premium-final-freeze python3 "$EVIDENCE/state.py" freeze "$EVIDENCE/tested-freeze.json" "$EVIDENCE/checkpoint.json" || exit $?
nav_record premium-candidate-freeze python3 - "$EVIDENCE/tested-freeze.json" "$EVIDENCE/tested-candidates.json" <<'PY' || exit $?
import json
import sys
from pathlib import Path
freeze = json.loads(Path(sys.argv[1]).read_text())
assert len(freeze['candidates']) == 25
with Path(sys.argv[2]).open('x') as output:
    json.dump(freeze['candidates'], output, indent=2, sort_keys=True)
print('Bound25 candidate blobs/modes from the actual pre-final-gates freeze')
PY
```
- [ ] Run exactly these sequential complete final groups with the mandatory preamble/cwd/timeout0. Read each complete raw summary before the next:

```bash
nav_record premium-final-requests rails_test test test/integration/premium_chat_header_test.rb test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/controllers/dashboards_controller_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/sources_workspace_shell_test.rb test/integration/chat_message_rendering_test.rb test/integration/token_footer_test.rb test/controllers/chat_account_access_test.rb test/models/chat_test.rb test/internationalization/catalogs_test.rb test/internationalization/view_copy_test.rb || exit $?
nav_record premium-final-native browser_test test/system/premium_chat_header_test.rb test/system/orbite_history_density_test.rb test/system/orbite_workspace_test.rb test/system/orbite_navigation_refinements_test.rb test/system/chat_workspace_test.rb test/system/compact_headers_test.rb test/system/chat_refresh_draft_test.rb || exit $?
nav_record premium-final-localization browser_test test/system/localization_test.rb || exit $?
nav_record premium-final-lint test_command bundle exec rubocop test/integration/premium_chat_header_test.rb test/integration/compact_headers_test.rb test/integration/chat_message_rendering_test.rb test/integration/token_footer_test.rb test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb test/controllers/dashboards_controller_test.rb test/controllers/settings_workspace_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/support/orbite_browser_checks.rb test/system/premium_chat_header_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/orbite_workspace_test.rb test/system/orbite_history_density_test.rb || exit $?
git diff --check
```

All test groups require nonzero test counts, actual seeds/assertions,0F/0E/0S,
true exit0 and unchanged final freeze. Node need not rerun: all JS is byte-frozen;
cite the actual inherited unchanged-source result honestly, not a future-SHA run.

```bash
nav_record premium-final-preservation python3 "$EVIDENCE/state.py" check "$EVIDENCE/tested-freeze.json" || exit $?
```

- [ ] Compare actual baseline and candidate records, not screenshots alone. For each of the16 identical locale/theme/viewport contexts, require equal chat/account/counts/kind values, matching reader width/height and dock boundary within1px, and strictly smaller header height/more transcript space for these ordinary fixtures. Long-name/large-count content is allowed to wrap; no fixed-height promise or reduction claim for arbitrary unlimited data. A failed comparison stops, not a reason to hide fields or shrink text.

Create the new external `compare-density.py` with this content and run it once
against this task's exclusive evidence root:

```python
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
before, after = {}, {}
for path in root.rglob('measurements.jsonl'):
    for line in path.read_text().splitlines():
        record = json.loads(line)
        label = record.get('label', '')
        destination = before if label.startswith('premium-density-before-') else after if label.startswith('premium-density-candidate-') else None
        if destination is None:
            continue
        key = (record['locale'], record['theme'], tuple(record['viewport']))
        assert key not in destination, (key, str(path))
        destination[key] = record['sample']
assert len(before) == len(after) == 16
assert before.keys() == after.keys()
results = []
for key in sorted(before):
    old, new = before[key], after[key]
    for field in ['chat', 'account', 'counts']:
        assert old[field] == new[field], (key, field)
    assert {row['kind']: row['values'] for row in old['kinds']} == {row['kind']: row['values'] for row in new['kinds']}, key
    for dimension in ['width', 'height']:
        assert abs(old['reader'][dimension] - new['reader'][dimension]) <= 1, (key, dimension)
    assert abs(old['dockTop'] - new['dockTop']) <= 1, key
    assert new['headerHeight'] < old['headerHeight'], (key, old['headerHeight'], new['headerHeight'])
    assert new['transcriptTop'] < old['transcriptTop'], key
    results.append({'context': key, 'before': old['headerHeight'], 'after': new['headerHeight'],
                    'transcript_gain': old['transcriptTop'] - new['transcriptTop']})
print(json.dumps({'same_fixture_contexts': 16, 'results': results}, indent=2))
```

```bash
nav_record premium-density-comparison python3 "$EVIDENCE/compare-density.py" "$EVIDENCE" || exit $?
```
- [ ] Open actual new originals for all four viewports, both locales/themes, zero/one-sided/large values, long account/full-value recovery, real live replacement, paused reader and native focus/draft contexts. Record exact paths/hashes/dimensions/observations and distinguish sample coverage from a complete human audit. Native zoom/SR/physical-device/provider checks remain NOT RUN.
- [ ] Parent/self-review the actual full diff, retire only table/duplicate-account contracts and preserve the approved History, reader/focus and shell corrections. Record all actual new failures and corrections with original receipts; no unchanged-source retry hunt.

### Tested-stage proof and conditional25-path commit

Only allGREEN, actual review and zero-change freezes permit staging. Write the
exact25 list above to a new external `candidates.txt`; freeze each candidate's
SHA256/blob/git mode before staging. Then use this proof before committing:

```python
import json
import subprocess
import sys
from pathlib import Path

root = Path('/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui')
freeze = json.loads(Path(sys.argv[1]).read_text())
paths = Path(sys.argv[2]).read_text().splitlines()
assert len(paths) == len(set(paths)) == 25
assert set(freeze) == set(paths)
def git(*args):
    return subprocess.check_output(['git', *args], cwd=root).decode()
assert not git('diff', '--cached', '--name-only')
subprocess.run(['git', 'add', '--', *paths], cwd=root, check=True)
assert set(git('diff', '--cached', '--name-only').splitlines()) == set(paths)
for path in paths:
    entry = git('ls-files', '--stage', '--', path).split()
    assert entry[:3] == [freeze[path]['gitMode'], freeze[path]['blob'], '0'], path
subprocess.run(['git', 'diff', '--cached', '--check'], cwd=root, check=True)
```

Run this external proof with absolute receipt paths while the shell's workdir
remains the repository:

```bash
nav_record premium-stage-proof python3 "$EVIDENCE/stage-proof.py" "$EVIDENCE/tested-candidates.json" "$EVIDENCE/candidates.txt" || exit $?
```

Export a new full-index
binary25-path diff and bind it to the freeze. Commit only after that proof:

```bash
git commit -m "feat(ui): Refine compact chat history and premium usage header"
```

Verify the actual commit parent is the plan commit, and each committed blob/mode
equals the tested freeze; the index is empty and only the five unchanged D drafts
remain dirty. No spec/plan/docs/generated CSS is staged. No push/merge/PR/cleanup.
The old18-path conditional commit is superseded by this coherent25-path boundary.

## Task 5 — Independent reviews, then bounded documentation reconciliation

- [ ] Parent inspects actual diff/raw logs/current original screenshots. Dispatch a fresh SPEC reviewer against the approved spec and this plan, then a **different** fresh QUALITY reviewer only after SPEC passes. No self-report-only acceptance and no final completion while Important/Critical findings remain. A fix requires a bounded test-first correction and affected fresh freezes/gates, not a waived assertion.
- [ ] Only after code reviews pass, use a fresh documentation implementer for the inherited five D drafts. Read their actual diffs; retain dated historical results, draft/source/upload/reader safeguards and accepted limits. Do not recreate them from an old template.
- [ ] Update current header descriptions in `docs/orbite-workspace.md` and `docs/chat-workspace.md` with this exact paragraph, linking relative to each owning doc:

```markdown
Saved conversations use a compact Usage band with one input/output distribution
bar, exact totals and visible input/output counts for every usage type. It shows
composition, not a quota or model limit. The full account appears once under the
title; complete environmental estimates and methodology/fallback notes remain
visible. No Usage table or accordion is hidden behind the bar. The same localized
live accounting target updates this server-rendered content. Home and History
remain outside the chat header, and New chat retains its existing action.
```

- [ ] In the current supersession notice of `docs/compact-headers.md`, add:

```markdown
The [premium chat header](superpowers/specs/2026-11-02-orbite-compact-premium-chat-header-design.md)
also replaces the duplicated toolbar account and Usage table with one full
account label, exact visible per-type lines and a passive input/output bar.
It does not change accounting, native input or paused-reader guarantees.
```

- [ ] In `docs/chat-composer.md`'s dedicated-shell section add: `The premium header changes only visible context and accounting presentation; it adds no composer control, draft owner or submission state.` Keep its native handoff and historical command warnings.
- [ ] In `docs/README.md` extend the existing Orbite guide description to `shared rail, responsive private history, compact live Usage band, reading surface, and reserved native composer.` Reconcile stale Delete/Home/History statements with already-requested removals, preserving backend authorization and historical sections, not restoring controls.
- [ ] Link the approved spec and this plan from the current guide. Verify relative links/anchors and exact doc diff. Leave all five D drafts unstaged; do not append invented results or an application-pass claim at the future documentation SHA.

Task D's broader final selections, missing security-baseline provenance decision
and independent whole-feature review remain separate pending work. The original
security artifacts were lost; do not silently regenerate a baseline against the
user's no-repeat instruction, claim a security-clean result, or automatically
commit/integrate documentation. Record current source-bound results separately
from historical640-test provenance and this new compactness comparison.

## Parent plan self-review / coverage

- Compact B, one bar, all numeric/impact information: Tasks1–2; no quota/hidden table.
- Full account once, old title bound, saved/new/no-account boundaries: Tasks1A,2A,3.
- Live root/background/no-Current/localized broadcasts and exact arithmetic: Tasks1A,2B,3A,4.
- Zero/one-sided/large counts, real geometry, themes/locales/native focus/contrast: Tasks1,4.
- Actual new-kind growth,±1px/80px/Latest/own-success and draft protections: unchanged strict full files plus Task3 selector-only migrations.
- History/rail/JS/backend immutability and five D draft preservation: Tasks0,3,4.
- Meaningful RED before code; current before/after evidence, frozen complete gates, tested25 blobs/modes: Tasks1,4.
- Independent SPEC→differentQUALITY and honest docs/security/integration limits: Task5.

This plan authors implementation instructions, not premium application changes.
No premium production/test implementation, baseline browser run, design RED or
application-test gate was performed by the plan author. The separate current-source
CSS proof is diagnostic compilation to an external artifact, not application or
test acceptance, old-provenance recovery or a repository asset replacement.
