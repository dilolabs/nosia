# Orbite History Density Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved editorial History list with more complete conversations at the same panel height, single-line title/account previews, and unchanged native navigation, privacy, deletion, and reader/composer behavior.

**Architecture:** Keep the existing authorized server-rendered list and `li > div > a` relationship. Move account/date context inside the ordinary link, apply History-only CSS ellipsis to title/account spans, preserve semantic dates and the separate native deletion form, and remove only redundant visible introductory chrome. One fresh implementer owns the coherent eight-path runtime/test change; after fresh SPEC then QUALITY review, a separate fresh implementer reconciles the five pending D drafts and refreshes all final evidence without staging them.

**Tech Stack:** Existing Rails 8.0.5.1 application, Ruby 4.0.7 through the original isolated helper, PostgreSQL test database, ERB, scoped Tailwind/plain CSS, Turbo/Stimulus unchanged, Minitest/fixtures, local Chromium/WebDriver.

---

## Authority, ownership, and non-negotiable boundaries

- Approved specification: [History density design](../specs/2026-10-31-orbite-history-density-design.md), including the user's explicit written-review **“Oui”**. The spec's approval metadata is parent-owned. Do not alter it.
- Planning-time HEAD is `b6cf5b681331c07d47f906c0d28d8d97016d3db5`, spec-only above reviewed runtime `f48760734132598ca0fdd9ca126f24cde8e36e24`. Execution may start after a plan/spec-only commit: record **actual** HEAD, verify its runtime still equals f487607, and never label a future commit as executed.
- Execution mode is already chosen: **fresh implementer per task, then independent fresh SPEC → fresh QUALITY**. Do not ask again. The parent self-reviews this plan; no plan-review dispatch. No new worktree, unrelated refactor, cleanup, integration, push, PR, or automatic documentation commit.
- Preserve the actual latest five D drafts byte-for-byte throughout Task 1: `docs/README.md`, `docs/chat-composer.md`, `docs/chat-workspace.md`, `docs/compact-headers.md`, and untracked `docs/orbite-workspace.md`. Snapshot hashes/bytes before work. Their earlier D owner `ses_e6dfac0a3ffeAiSVdeOqukY067` returned READY_FOR_REVIEW, **not a documentation commit**.
- All production JavaScript, reader/dock algorithms and markup, helper/backend/locale/schema/fixture/dependency/authorization/accounting/source/Formatting/Stop behavior remain unchanged. Inline panel stays **240px**. `chat_workspace_title` already bounds display previews to 120 characters; do not change it or promise the entire first message in History.
- Ordinary link activation provides keyboard/touch access to the original question in the wrapping transcript and the full account in the paragraph under Usage. The saved toolbar `h1` and account preview remain clipped under their existing compact-header contracts; full source values remain in their DOM. Native `title` attributes supplement recovery; no custom tooltip, disclosure control, focus owner, or JavaScript.
- Do not shrink the existing 14px link/body typography, 12px metadata, or 44px targets to manufacture density. Dates must remain complete and may wrap; never ellipsize dates or impose a clipping height.
- Unexpected nonzero/F/E/S means **BLOCKED**, with original raw logs and true exits. The only deliberate exceptions are separately recorded meaningful design RED, and the expected Brakeman scanner exit **3** followed by parsed comparison exit **0**. A boot error is not RED. A baseline characterization PASS is not RED. No retry hunt, weakening an oracle, or silently expanding ownership.

### File map

| Task | Exact owned path | Responsibility |
| --- | --- | --- |
| 1 | `app/views/chats/_history_items.html.erb` | Remove introductory help; full title/account spans and native title attributes inside existing link; unchanged trash form |
| 1 | `app/views/application/_orbite_shell.html.erb` | Remove visible History `h3` only |
| 1 | `app/assets/stylesheets/nosia/orbite_chat.css` | Replace scoped History block only |
| 1 | `app/assets/stylesheets/nosia/orbite_shell.css` | Delete obsolete single-column History override and unused heading rule only |
| 1 | `test/integration/orbite_shell_test.rb` | New escaping/chrome/label contracts; coupled account `p`→span assertion migration |
| 1 | `test/controllers/chat_workspace_test.rb` | Only bounded-title test's History selector targets inner title span |
| 1 | `test/system/orbite_workspace_test.rb` | Existing eight History cases and `orbite_history_rows` sampler only; preserve native traversal helpers |
| 1 | **new** `test/system/orbite_history_density_test.rb` | Permanent density characterization, meaningful native design RED, compact-label/native-recovery matrix |
| 2 | The five D drafts listed above **only** | Reconcile current History documentation and refresh final verified results; leave unstaged |

No shared helper/fixture/other-test edit is authorized. `test/system/compact_headers_test.rb`, `test/system/chat_workspace_test.rb`, `test/system/chat_refresh_draft_test.rb`, and all deletion/privacy/source oracles run unchanged. Current actual `test/controllers/chat_workspace_test.rb:55–69` contains **one History whole-link text assertion at line 68**, plus the independent `h1` assertion at line 63. Change the former selector only; keep the latter and transcript/source-length assertions unchanged. Do not interpret an approximate “two assertions” count as permission to modify a second unrelated assertion.

## Common execution protocol (not executed by this plan author)

Every **new shell call** uses this complete preamble and the exact cwd shown, including static/evidence commands. Do not assume shell variables survive calls. The helper is read-only and is **not a network sandbox**.

```bash
# cwd: /home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui
source /tmp/opencode/chat-workspace-env.sh || exit $?
export E=/tmp/opencode/chat-workspace-recovery-Pbwj0x
export EVIDENCE="$E"
export ORBITE_SOURCE_SHA="$(git rev-parse HEAD)"
source "$E/orbite-refinement-record.sh" || exit $?
```

Use `nav_record`, not a guessed `task0-recorder.sh`. Run every build/test/browser/scanner foreground with tool **timeout=0**, sequentially; await actual completion, never poll/sleep/overlap. Read the complete resulting originals, not only the recorder's last 30 lines. Record exact invocation, cwd, actual HEAD, freeze, raw path/hash, adjacent `.TRUE.exit`, seed/count/assertions/F/E/S. No `.env` contents, DEV-process inspection/control, DB setup/migrate/reset, install, worker/queue drain, live AI/MCP/crawl/index/embedding, unsafe unrestricted suite, or driver/transport change.

Reserve unique append-only external paths. The following convention applies to each new evidence prefix: reserve a marker with `mktemp`, keep it, write to new sibling names with exclusive creation. Keep original failures, old D results, scans, receipts and evidence indices intact.

### External checkpoint/freeze utility

Task 1 creates this **external**, uniquely named file with the patch tool as `$E/orbite-history-density-state-v1.py`. If that name already exists, choose a new unused `vN` suffix and consistently use it; never overwrite an earlier script. This is not a ninth repository mutation. It deliberately accepts actual current HEAD rather than hardcoding f487607. It explicitly includes the new untracked native test and all five drafts, protects installed inputs and the original 238-file map, and proves the exact staged/tested eight blobs.

```python
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path('/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui')
E = Path('/tmp/opencode/chat-workspace-recovery-Pbwj0x')
DOCS = ['docs/README.md', 'docs/chat-composer.md', 'docs/chat-workspace.md',
        'docs/compact-headers.md', 'docs/orbite-workspace.md']
OWNED = ['app/views/chats/_history_items.html.erb',
         'app/views/application/_orbite_shell.html.erb',
         'app/assets/stylesheets/nosia/orbite_chat.css',
         'app/assets/stylesheets/nosia/orbite_shell.css',
         'test/integration/orbite_shell_test.rb',
         'test/controllers/chat_workspace_test.rb',
         'test/system/orbite_workspace_test.rb',
         'test/system/orbite_history_density_test.rb']
INPUTS = ['app', 'test', 'config', 'lib', 'db', 'vendor', 'bin', 'Gemfile',
          'Gemfile.lock', '.ruby-version', '.rubocop.yml', 'AGENTS.md', 'docs']

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def safe(path):
    path = Path(path)
    assert not any(p == '.env' or p.startswith('.env.') for p in path.parts), str(path)
    assert path.is_file() and not path.is_symlink(), str(path)
    return path

def sha(path):
    return hashlib.sha256(safe(path).read_bytes()).hexdigest()

def current():
    assert Path.cwd() == ROOT
    names = set(filter(None, git('ls-files', '-z', '--', *INPUTS).decode().split('\0')))
    names.update(DOCS)
    if (ROOT / OWNED[-1]).exists():
        names.add(OWNED[-1])
    untracked = set(filter(None, git('ls-files', '--others', '--exclude-standard', '-z',
                                    '--', *INPUTS).decode().split('\0')))
    assert untracked <= {DOCS[-1], OWNED[-1],
                         'docs/superpowers/plans/2026-10-31-orbite-history-density.md'}, untracked
    names.update(untracked)
    files = {}
    for name in sorted(names):
        rel = Path(name)
        assert not rel.is_absolute() and '..' not in rel.parts, name
        data = safe(ROOT / name).read_bytes()
        files[name] = {'sha256': hashlib.sha256(data).hexdigest(),
                       'blob': hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest(),
                       'mode': '100755' if (ROOT / name).stat().st_mode & 0o111 else '100644'}
    start = json.loads((E / 'orbite-refinement-start-20261031T134434Z-56aea0dc.json').read_text())
    assert len(start['protectedSHA256']) == 238
    for name, digest in start['protectedSHA256'].items():
        assert sha(ROOT / name) == digest, name
    installed = json.loads((E / 'orbite-refinement-D-protected-baseline-inputs.json').read_text())
    for name, digest in installed['installedSources'].items():
        assert sha(name) == digest, name
    assert sha('/tmp/opencode/chat-workspace-env.sh') == installed['helperSHA256']
    assert sha(E / 'orbite-refinement-record.sh') == installed['recorderSHA256']
    assert sha(ROOT / 'app/views/messages/_form.html.erb') == installed['messagesFormSHA256']
    return {'head': git('rev-parse', 'HEAD').decode().strip(), 'files': files,
            'protected': start['protectedSHA256'], 'installed': installed}

mode, filename = sys.argv[1:3]
path = Path(filename)
now = current()
if mode in ('create', 'checkpoint'):
    assert not git('diff', '--cached', '--name-only'), 'Index must be empty'
    if mode == 'checkpoint':
        assert not git('diff', 'f48760734132598ca0fdd9ca126f24cde8e36e24', '--',
                       *[p for p in INPUTS if p != 'docs' and p != 'AGENTS.md'])
        prior = json.loads((E / 'orbite-refinement-D-final-receipt.json').read_text())
        assert {n: sha(ROOT / n) for n in DOCS} == prior['finalDocSHA256']
        snapshots = path.with_name(path.name + '.drafts')
        snapshots.mkdir()
        for name in DOCS:
            with (snapshots / Path(name).name).open('xb') as output:
                output.write(safe(ROOT / name).read_bytes())
    with path.open('x') as output:
        json.dump(now, output, indent=2, sort_keys=True)
elif mode in ('ownership', 'check', 'check-runtime', 'staged', 'committed'):
    old = json.loads(path.read_text())
    assert old['protected'] == now['protected']
    assert old['installed'] == now['installed']
    allowed = set(OWNED) if mode == 'ownership' else set(DOCS) if mode == 'check-runtime' else set()
    changed = {n for n in old['files'].keys() | now['files'].keys()
               if n not in allowed and old['files'].get(n) != now['files'].get(n)}
    assert not changed, sorted(changed)
    if mode == 'committed':
        assert git('rev-parse', 'HEAD^').decode().strip() == old['head']
        assert set(git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').decode().splitlines()) == set(OWNED)
        for name in OWNED:
            assert git('rev-parse', 'HEAD:' + name).decode().strip() == old['files'][name]['blob'], name
            assert git('ls-tree', 'HEAD', '--', name).decode().split()[0] == old['files'][name]['mode'], name
    else:
        assert now['head'] == old['head'], (old['head'], now['head'])
    if mode == 'staged':
        assert set(git('diff', '--cached', '--name-only').decode().splitlines()) == set(OWNED)
        for name in OWNED:
            assert git('rev-parse', ':' + name).decode().strip() == old['files'][name]['blob'], name
            assert git('ls-files', '--stage', '--', name).decode().split()[0] == old['files'][name]['mode'], name
        patch = git('diff', '--cached', '--binary', '--full-index')
        with Path(sys.argv[3]).open('xb') as output:
            output.write(patch)
        print('TESTED_STAGED_PATCH_SHA256', hashlib.sha256(patch).hexdigest())
else:
    raise ValueError(mode)
print(json.dumps({'mode': mode, 'head': now['head'], 'receipt': str(path),
                  'receiptSHA256': sha(path), 'fileCount': len(now['files']),
                  'protectedCount': 238, 'result': 'PASS'}, indent=2))
```

The utility is evidence plumbing, not authorization to edit its inputs. Parent-owned spec/plan changes after checkpoint require a new explicit checkpoint; never silently exclude them to get a green check. Task 2 uses `check-runtime` only for its planned post-gate doc footer, then creates a new full freeze and reviews the exact five-doc delta. Read the actual historical receipt before trusting any key: `artifactSHA256` names in D's final receipt are **relative to E, not the repository**.

## Task 1: Implement the coherent editorial History amendment

**Owner:** One fresh bounded implementer; exactly the eight runtime/test paths above. External scripts/audit/logs are uniquely named under E. No D draft edits. No production mutation until actual-source audit, baseline characterization, and meaningful request/native RED have completed.

### Execution clarification for the stopped first candidate

The first implementer correctly stopped before the whole native gate: the plan
had incorrectly described clipped toolbar previews as wrapping. Actual
`application_shell.css:45–46` and the unchanged compact-header regression require
those previews to stay clipped. This is a plan/test-target error, not an observed
product regression. Do not change header CSS, header markup, compact-header tests,
or any of the four already-tested History production paths to resolve it.

The parent authorizes only a corrected full-value recovery assertion in the NEW
native file: after genuine Enter navigation, read the complete original question
from `.n-chat-transcript .n-chat-user-body` and the full account from
`#chat-usage-details > p`. Keep original `h1`/toolbar-account full DOM text checks
and their existing compact presentation. Retain all list clipping/contrast/native
focus/date/deletion/privacy/reader oracles. First collect a passive original
geometry/text trace at one real 375px spaced-label case; if these existing reading
surfaces do not actually wrap and contain their complete text, return BLOCKED
rather than changing production or weakening containment.

Original prefix: `/tmp/opencode/chat-workspace-recovery-Pbwj0x/orbite-history-density-task1.s4CHKX`.
Original stopped freeze and all logs/comparisons remain immutable. The parent
preserved all eight source files plus the two pre-clarification docs in
`orbite-history-parent-clarification-77gp48k_.originals/`; its `.json` receipt binds
the exact original new-test SHA256 `40aa18273ef92391ba6af8a32bbb74e70f47fd409121159cac089258a65738f1`.

The clarification changes only two parent-owned Markdown files and the new
native test's recovery block/helper. Use a NEW continuation prefix/checkpoint and
external state utility, never rewrite the old receipts/scripts. Before modifying
the test, verify every stopped input still matches the original tested freeze
except the two explicitly committed clarification docs. The new checkpoint must
inherit the old protected/nonowned/draft maps, changing only the two approved doc
entries, documentation HEAD and its corresponding index identities. Preserve the
original checkpoint's expected five-draft-only status for post-eight-path-commit
verification. Do not re-run the original “runtime equals f487607” checkpoint on an
already-modified candidate or pretend the original tests ran at the new docs HEAD.

The entire new test file can no longer remain byte-identical once its erroneous
recovery block is corrected. This narrow exception does NOT relax the permanent
density characterization. Keep its setup, fixture construction, expected
semantics, viewport/opener logic, test body and sampler byte-identical. Create a
NEW exclusive proof from the preserved original and corrected current file using:

```python
import hashlib
import json
from pathlib import Path
import sys

root = Path('/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui')
e = Path('/tmp/opencode/chat-workspace-recovery-Pbwj0x')
name = 'test/system/orbite_history_density_test.rb'
original = e / 'orbite-history-parent-clarification-77gp48k_.originals' / name
old = original.read_text()
new = (root / name).read_text()
assert hashlib.sha256(original.read_bytes()).hexdigest() == '40aa18273ef92391ba6af8a32bbb74e70f47fd409121159cac089258a65738f1'

def units(text):
    def span(first, following):
        start = text.index(first)
        return text[start:text.index(following, start)]
    return {
        'prelude_setup_teardown': text[:text.index('  test "density characterization')],
        'characterization_test': span('  test "density characterization', '  test "native design'),
        'seed': span('    def density_seed', '    def density_expected'),
        'expected_semantics': span('    def density_expected', '    def density_open'),
        'viewport_opener': span('    def density_open', '    def density_characterization'),
        'characterization_sampler': span('    def density_characterization', '    def density_rows'),
    }

before, after = units(old), units(new)
assert before == after, 'Permanent density characterization changed'
proof = {'scope': 'Recovery-test correction only; permanent real density units unchanged',
         'originalFile': str(original), 'originalSHA256': hashlib.sha256(original.read_bytes()).hexdigest(),
         'currentSHA256': hashlib.sha256((root / name).read_bytes()).hexdigest(),
         'unitSHA256': {key: hashlib.sha256(value.encode()).hexdigest() for key, value in before.items()}}
with Path(sys.argv[1]).open('x') as stream:
    json.dump(proof, stream, indent=2)
print('PASS six permanent density units byte-identical; full recovery test changed separately')
```

This proof replaces ONLY the continuation comparison's whole-file equality check;
the initial original comparison remains valid for its original unchanged file.
Run a NEW after-characterization and compare it with the same original baseline,
retaining identical fourteen-row semantics, original path/hash/line provenance,
zero scroll origin, same panel/content dimensions within1px and strict improvement
in all eight contexts. New candidate freezes bind the corrected test and current
documentation HEAD. Re-audit actual changed test source, run all focused requests,
native cases, complete six-file native group, localization and four-file lint on
the new freeze, then exact eight-path commit/blob proof and fresh SPEC→QUALITY.
No old focused results substitute for these new final gates.

- [ ] **Step 1: Establish the static safety/source/draft checkpoint.**

Read the entire approved spec, this plan, all eight current touchpoints, the original helper/recorder, `test/{test_helper,application_system_test_case}.rb`, `test/support/{chat_workspace_fixtures,chat_account_fixtures,orbite_browser_checks}.rb`, fixture YAML, schema, Chat/Message/User, `ChatWorkspacesHelper`, and actual controller/rendering paths. Read D's actual report, manifest, command receipts, safety audit, final receipt and original referenced source/protection maps. Check that no implementer/runtime verification group is active by parent coordination, **not by inspecting user processes**.

Create the external utility above with the patch tool. With common preamble:

```bash
H="$(mktemp "$E/orbite-history-density-task1.XXXXXX")" || exit $?
printf '%s\n' "$H" > "${H}.prefix"
nav_record orbite-history-density-checkpoint python3 "$E/orbite-history-density-state-v1.py" checkpoint "${H}.checkpoint.json" || exit $?
git status --short
git diff -- docs/README.md docs/chat-composer.md docs/chat-workspace.md docs/compact-headers.md
```

Keep H's actual prefix in the task report and supply its literal returned path in each subsequent shell call (assign the recorded actual path to H, not a new random prefix each time). Read the untracked guide in full. The checkpoint code copies the five regular draft files into its exclusively created `.drafts` sibling directory without modifying originals and records their hashes. Expected: empty index; only the known five drafts and parent-owned spec/plan may be dirty; runtime equals f487607; all238 protected, ten installed inputs, helper/recorder/form match.

- [ ] **Step 2: Add the complete new native test file and actual-source-audit it before running.**

Create `test/system/orbite_history_density_test.rb` with the following complete source. Keep the permanent characterization method, its fixed sample, and sampler unchanged between baseline/candidate. This file uses real persisted fixture-owned roots and callback-free inserts, not rendered fake rows or an environment-provided pass threshold.

```ruby
require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/orbite_browser_checks"

class OrbiteHistoryDensitySystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include OrbiteBrowserChecks

  VIEWPORTS = [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].freeze

  setup do
    @original_size = page.current_window.size
    density_seed
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(*@original_size) if @original_size
  end

  test "density characterization records ordinary complete rows" do
    %w[en fr].product([ false, true ], [ [ 1400, 1000 ], [ 375, 812 ] ]).each do |locale, dark, (width, height)|
      orbite_viewport(width, height)
      orbite_select_language(locale.upcase)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      orbite_theme(dark)
      density_open(width)
      sample = density_characterization
      expected = @user.recent_conversations.map do |chat|
        { "id" => chat.id.to_s, "title" => @density_titles.fetch(chat.id),
          "account" => chat.account.name, "datetime" => chat.updated_at.iso8601,
          "date" => I18n.l(chat.updated_at, format: :short, locale: locale) }
      end
      assert_equal expected, sample.fetch("rows").map { |row| row.slice("id", "title", "account", "datetime", "date") }
      assert_equal 14, sample.fetch("rows").length
      assert_operator sample.fetch("fullyVisible"), :>, 0, sample.to_json
      assert_operator sample.fetch("fullyVisible"), :<, sample.fetch("rows").length, sample.to_json
      assert_equal [ width, height ], sample.fetch("viewport")
      assert_equal width >= 1280 ? "inline" : "modal", sample.fetch("mode")
      assert_operator sample.fetch("overflow"), :<=, 0, sample.to_json
      orbite_record("history-density-characterization-#{locale}-#{dark}-#{width}x#{height}", sample, screenshot: true)
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "native design removes only redundant History chrome" do
    orbite_viewport(375, 812)
    visit chat_path(@chat)
    density_open(375)
    assert_selector "#chat-history h2#chat-history-title.sr-only", text: "Navigation", visible: :all
    assert_selector "#chat-history[aria-labelledby=chat-history-title] [data-orbite-history][aria-label]"
    assert_no_selector "[data-orbite-history] h3", visible: :all
    assert_no_selector "[data-orbite-history] > p:not([data-history-empty])", visible: :all
    assert_selector "#chat-history .n-orbite-panel-links a", minimum: 1
    orbite_tab_to("#workspace-navigation-close")
    page.driver.browser.action.send_keys(:enter).perform
    assert_no_selector "#chat-history[open]", visible: :all
    assert_selector "#workspace-history-trigger:focus"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "native design places compact labels beside trash" do
    @second.update_columns(name: "CompteDeRecherche" * 12)
    orbite_viewport(1400, 1000)
    visit chat_path(@chat)
    density_open(1400)
    sample = density_row(@chat.id)
    assert_operator sample.fetch("button").fetch("left"), :>=, sample.fetch("body").fetch("right"), sample.to_json
    %w[title account].each do |part|
      label = sample.fetch(part)
      assert_equal "nowrap", label.fetch("whiteSpace"), sample.to_json
      assert_equal "ellipsis", label.fetch("textOverflow"), sample.to_json
      assert_equal "hidden", label.fetch("overflowX"), sample.to_json
      assert_operator label.fetch("box").fetch("height"), :<=, label.fetch("lineHeight") + 1, sample.to_json
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  %w[en fr].product([ false, true ], VIEWPORTS, %w[spaced unspaced]).each do |locale, dark, (width, height), kind|
    test "compact label matrix #{locale} #{dark} #{width}x#{height} #{kind}" do
      long_title = kind == "spaced" ? ("Long conversation labels " * 8).strip : "UnbrokenConversation" * 10
      long_account = kind == "spaced" ? ("Long research account " * 9).strip : "CompteDeRecherche" * 12
      short_id, long_id = @density_ids.first(2)
      @first.update_columns(name: "Lab")
      @second.update_columns(name: long_account)
      Message.where(chat_id: short_id, role: :user).update_all(content: "OK")
      Message.where(chat_id: long_id, role: :user).update_all(content: long_title)
      preview = long_title.first(119) + "…"
      orbite_viewport(width, height)
      orbite_select_language(locale.upcase)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      orbite_theme(dark)
      density_open(width)
      assert_no_selector "[data-orbite-history] h3, [data-orbite-history] > p:not([data-history-empty])", visible: :all
      [ [ short_id, "OK", "Lab" ], [ long_id, preview, long_account ] ].each do |id, title, account|
        row = "#chat-history [data-history-chat='#{id}']"
        assert_selector "#{row} .n-chat-history-title", visible: true
        assert_selector "#{row} .n-chat-history-account", visible: true
        sample = density_row(id)
        assert_equal title, sample.fetch("title").fetch("text")
        assert_equal title, sample.fetch("nativeTitle")
        assert_equal account, sample.fetch("account").fetch("text")
        assert_equal account, sample.fetch("nativeAccount")
        assert_includes sample.fetch("linkText"), title
        assert_includes sample.fetch("linkText"), account
        %w[title account].each do |part|
          label = sample.fetch(part)
          assert_equal "nowrap", label.fetch("whiteSpace"), label.to_json
          assert_equal "ellipsis", label.fetch("textOverflow"), label.to_json
          assert_equal "hidden", label.fetch("overflowX"), label.to_json
          assert_operator label.fetch("box").fetch("width"), :>, 0, label.to_json
          assert_operator label.fetch("box").fetch("height"), :<=, label.fetch("lineHeight") + 1, label.to_json
          assert_operator label.fetch("contrast"), :>=, 4.5, label.to_json
          if id == long_id
            assert_operator label.fetch("scrollWidth"), :>, label.fetch("clientWidth"), label.to_json
          else
            assert_operator label.fetch("scrollWidth"), :<=, label.fetch("clientWidth"), label.to_json
          end
        end
        chat = Chat.find(id)
        assert_equal chat.updated_at.iso8601, sample.fetch("datetime")
        assert_equal I18n.l(chat.updated_at, format: :short, locale: locale), sample.fetch("date").fetch("text")
        refute_equal "ellipsis", sample.fetch("date").fetch("textOverflow")
        assert sample.fetch("dateFits"), sample.to_json
        assert_operator sample.fetch("date").fetch("contrast"), :>=, 4.5, sample.to_json
        assert_operator sample.fetch("button").fetch("left"), :>=, sample.fetch("body").fetch("right"), sample.to_json
        assert_operator sample.fetch("link").fetch("width"), :>=, [ sample.fetch("row").fetch("width"), sample.fetch("fontSize") * 8 ].min
        assert_in_delta 14, sample.fetch("fontSize"), 0.1
        assert_in_delta 12, sample.fetch("metadataFontSize"), 0.1
        assert_operator sample.fetch("account").fetch("box").fetch("width"), :>=,
          [ sample.fetch("title").fetch("box").fetch("width"), sample.fetch("metadataFontSize") * 4 ].min
        %w[link button].each do |part|
          assert_operator sample.fetch(part).fetch("width"), :>=, 44, sample.to_json
          assert_operator sample.fetch(part).fetch("height"), :>=, 44, sample.to_json
        end
        assert_equal 0, sample.fetch("documentOverflow")
        assert_operator sample.fetch("contentOverflow"), :<=, 0
        assert_equal I18n.t("nosia.actions.confirm_delete", locale: locale), find("#{row} button")["data-turbo-confirm"]
        orbite_record("history-compact-#{locale}-#{dark}-#{width}-#{kind}-#{id}", sample, screenshot: true)
      end
      selectors = [ short_id, long_id ].flat_map do |id|
        [ "[data-history-chat='#{id}'] > div > a", "[data-history-chat='#{id}'] button" ]
      end
      selectors.each { |selector| density_tab_to(selector) }
      selectors.reverse_each { |selector| density_tab_to(selector, reverse: true) }
      close = density_tab_to("#workspace-navigation-close")
      assert_operator close.fetch("width"), :>=, 44
      assert_operator close.fetch("height"), :>=, 44
      if width < 1280
        page.driver.browser.action.send_keys(:escape).perform
        assert_no_selector "#chat-history:modal"
        opener = width >= 768 ? "#workspace-history-rail-trigger" : "#workspace-history-trigger"
        assert_selector "#{opener}:focus"
        page.driver.browser.action.send_keys(:enter).perform
        assert_selector "#chat-history:modal"
      end
      density_tab_to("[data-history-chat='#{long_id}'] > div > a")
      page.driver.browser.action.send_keys(:enter).perform
      assert_current_path chat_path(long_id)
      assert_selector ".n-chat-header h1", text: preview, exact_text: true
      assert_selector ".n-chat-header [data-chat-account-label]", text: long_account, exact_text: true
      assert_selector ".n-chat-transcript .n-chat-user-body", text: long_title, exact_text: true
      assert_selector "#chat-usage-details > p", text: long_account, exact_text: true
      recovery = page.evaluate_script(<<~JS)
        ['.n-chat-transcript .n-chat-user-body', '#chat-usage-details > p'].map(selector => {
          const node = document.querySelector(selector)
          const style = getComputedStyle(node), box = node.getBoundingClientRect(), range = document.createRange()
          range.selectNodeContents(node)
          return { text: node.textContent.trim(), whiteSpace: style.whiteSpace, overflow: style.overflowX,
            textOverflow: style.textOverflow, fits: [...range.getClientRects()].every(r => r.left >= box.left - 1 && r.right <= box.right + 1) }
        })
      JS
      assert_equal [ long_title, long_account ], recovery.map { |item| item.fetch("text") }
      recovery.each do |item|
        refute_equal "nowrap", item.fetch("whiteSpace")
        refute_equal "hidden", item.fetch("overflow")
        refute_equal "ellipsis", item.fetch("textOverflow")
        assert item.fetch("fits"), item.to_json
      end
      orbite_record("history-native-open-#{locale}-#{dark}-#{width}-#{kind}", recovery, screenshot: true)
      assert_equal 0, page.evaluate_script("document.scrollingElement.scrollTop")
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      assert page.evaluate_script("[...document.querySelectorAll('#chat-history a, #chat-history button')].every(node => getComputedStyle(node).transitionDuration.split(',').every(value => parseFloat(value) === 0))")
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  private
    def density_seed
      stamp = Time.utc(2026, 10, 31, 10)
      @first.update_columns(name: "Lab")
      @second.update_columns(name: "Research")
      first = workspace(:chats, :workspace_first_chat)
      first.update_columns(created_at: Time.utc(2026, 10, 19, 10), updated_at: Time.utc(2026, 10, 19, 10))
      @chat.update_columns(created_at: Time.utc(2026, 10, 20, 10), updated_at: Time.utc(2026, 10, 20, 10))
      @density_ids = 12.times.map { |i| ActiveRecord::FixtureSet.identify("orbite_density_chat_#{i}") }
      message_ids = 12.times.map { |i| ActiveRecord::FixtureSet.identify("orbite_density_message_#{i}") }
      assert_equal 12, @density_ids.uniq.length
      assert_equal 12, message_ids.uniq.length
      assert_equal 0, Chat.where(id: @density_ids).count
      assert_equal 0, Message.where(id: message_ids).count
      @density_titles = { first.id => "First account question", @chat.id => "What are the key findings in this report?" }
      Chat.insert_all!(@density_ids.each_with_index.map do |id, i|
        { id: id, user_id: @user.id, account_id: i.even? ? @first.id : @second.id,
          ruby_llm_model_id: @chat.ruby_llm_model_id, chat_id: nil,
          created_at: stamp - i.minutes, updated_at: stamp - i.minutes }
      end)
      Message.insert_all!(@density_ids.each_with_index.map do |id, i|
        title = "History sample #{format("%02d", i + 1)}"
        @density_titles[id] = title
        { id: message_ids.fetch(i), chat_id: id, role: 20, response_number: 0,
          content: title, created_at: stamp - i.minutes, updated_at: stamp - i.minutes }
      end)
    end

    def density_open(width)
      if width >= 1280
        assert_selector "#chat-history[data-inline=true][open]"
      else
        unless page.has_selector?("#chat-history:modal", wait: 0)
          find(width >= 768 ? "#workspace-history-rail-trigger" : "#workspace-history-trigger").click
        end
        assert_selector "#chat-history:modal"
      end
      orbite_settle
    end

    def density_characterization
      page.evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector('#chat-history'), content = panel.querySelector('.n-orbite-panel-content')
          const list = panel.querySelector('.n-chat-history-list'), rect = node => node.getBoundingClientRect().toJSON()
          const port = rect(content)
          const rows = [...list.querySelectorAll('[data-history-chat]')].map(row => {
            const link = row.querySelector(':scope > div > a'), time = row.querySelector('time')
            const title = row.querySelector('.n-chat-history-title') || link
            const account = row.querySelector('.n-chat-history-account') || row.querySelector(':scope > div > p')
            const bounds = rect(row)
            return { id: row.dataset.historyChat, title: title.textContent.trim(), account: account.textContent.trim(),
              datetime: time.getAttribute('datetime'), date: time.textContent.trim(), bounds,
              complete: bounds.top >= port.top && bounds.bottom <= port.bottom && bounds.left >= port.left && bounds.right <= port.right }
          })
          return { version: 1, mode: panel.matches(':modal') ? 'modal' : 'inline', viewport: [innerWidth, innerHeight],
            panel: rect(panel), content: port, list: rect(list), scrollTop: content.scrollTop,
            overflow: Math.max(document.documentElement.scrollWidth - innerWidth, content.scrollWidth - content.clientWidth),
            rows, fullyVisible: rows.filter(row => row.complete).length }
        })()
      JS
    end

    def density_row(id)
      page.evaluate_script(<<~JS, id.to_s)
        (() => {
          const row = document.querySelector(`[data-history-chat="${arguments[0]}"]`), body = row.querySelector(':scope > div')
          const link = body.querySelector('a'), button = row.querySelector('button'), time = row.querySelector('time')
          const title = row.querySelector('.n-chat-history-title') || link
          const account = row.querySelector('.n-chat-history-account') || body.querySelector('p')
          const rect = node => node.getBoundingClientRect().toJSON()
          const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
          const ctx = canvas.getContext('2d', { willReadFrequently: true })
          const lum = rgb => [...rgb].slice(0, 3).map(v => v / 255).map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4)
            .reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0)
          const contrast = (node, color) => {
            ctx.clearRect(0, 0, 1, 1); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, 1, 1)
            const chain = []; for (let n = node; n; n = n.parentElement) chain.push(n)
            chain.reverse().forEach(n => { ctx.fillStyle = getComputedStyle(n).backgroundColor; ctx.fillRect(0, 0, 1, 1) })
            const background = lum(ctx.getImageData(0, 0, 1, 1).data)
            ctx.fillStyle = color; ctx.fillRect(0, 0, 1, 1)
            const foreground = lum(ctx.getImageData(0, 0, 1, 1).data)
            return (Math.max(background, foreground) + .05) / (Math.min(background, foreground) + .05)
          }
          const label = node => {
            const s = getComputedStyle(node)
            return { text: node.textContent.trim(), box: rect(node), whiteSpace: s.whiteSpace, overflowX: s.overflowX,
              textOverflow: s.textOverflow, lineHeight: parseFloat(s.lineHeight), clientWidth: node.clientWidth,
              scrollWidth: node.scrollWidth, contrast: contrast(node, s.color) }
          }
          const t = rect(time), l = rect(link), range = document.createRange(); range.selectNodeContents(time)
          const s = getComputedStyle(link), content = row.closest('.n-orbite-panel-content')
          return { id: row.dataset.historyChat, row: rect(row), body: rect(body), link: l, button: rect(button),
            title: label(title), account: label(account), date: label(time), datetime: time.getAttribute('datetime'),
            dateFits: t.left >= l.left && t.right <= l.right && t.top >= l.top && t.bottom <= l.bottom &&
              [...range.getClientRects()].every(r => r.left >= t.left - 1 && r.right <= t.right + 1 && r.top >= t.top - 1 && r.bottom <= t.bottom + 1),
            nativeTitle: link.getAttribute('title'), nativeAccount: account.getAttribute('title'), linkText: link.textContent,
            fontSize: parseFloat(s.fontSize), metadataFontSize: parseFloat(getComputedStyle(account).fontSize),
            documentOverflow: document.documentElement.scrollWidth - innerWidth,
            contentOverflow: content.scrollWidth - content.clientWidth,
            buttonContrast: contrast(button, getComputedStyle(button).color),
            focusContrast: contrast(document.activeElement, getComputedStyle(document.activeElement).outlineColor) }
        })()
      JS
    end

    def density_tab_to(selector, reverse: false)
      sample = orbite_tab_to(selector, reverse: reverse)
      if selector != "#workspace-navigation-close"
        port = page.evaluate_script("document.querySelector('#chat-history .n-orbite-panel-content').getBoundingClientRect().toJSON()")
        %w[top left].each { |edge| assert_operator sample.fetch(edge), :>=, port.fetch(edge), sample.to_json }
        %w[bottom right].each { |edge| assert_operator sample.fetch(edge), :<=, port.fetch(edge), sample.to_json }
        id = page.evaluate_script("document.activeElement.closest('[data-history-chat]').dataset.historyChat")
        colors = density_row(id)
        assert_operator colors.fetch("focusContrast"), :>=, 3, colors.to_json
        assert_operator colors.fetch("buttonContrast"), :>=, 3, colors.to_json
        tag = page.evaluate_script("document.activeElement.tagName")
        orbite_record("history-native-focus-#{reverse}-#{id}-#{tag}", colors, screenshot: true)
      end
      assert_operator sample.fetch("outlineWidth"), :>=, 2
      assert sample.fetch("focusVisible")
      sample
    end
end
```

Static audit requirements **before any build/browser/request boot**:

1. Re-read the entire actual new file after patching, not just this proposed block. Verify actual callbacks/defaults in `db/schema.rb`, Chat/Message and installed RubyLLM macros, plus `/home/cbldev/.local/share/mise/installs/ruby/4.0.7/lib/ruby/gems/4.0.0/gems/activerecord-8.0.5.1/lib/active_record/{relation,insert_all}.rb` (`relation.rb:800` delegates `insert_all!`). Actual IDs are bigint fixture hashes; role is **20**; use existing `ruby_llm_model_id`. Do not substitute `Chat.create!`, `RubyLLM.chat`, `.ask`, `.complete`, provider refresh or message callbacks. `insert_all!` is callback-free and the source strings contain no URLs/sources/attachments. Existing membership/account/user/model rows come from ChatWorkspaceFixtures. The full-value reading surfaces are `.n-chat-transcript .n-chat-user-body` and `#chat-usage-details > p`; the toolbar previews intentionally remain clipped.
2. Audit inherited setup/teardown, fixture creation, test adapter selection/restore, ActiveJob railtie/helper, SolidQueue enqueue-only implementation, Cable local adapter, local login/GET/preferences/assets. Confirm no job execution/drain/perform flags. The twelve extra roots and messages are transactionally test-owned; no schema/setup/reset command is needed. `User#recent_conversations` has no limit and orders updated_at/id descending. Fixed timestamps and deterministic IDs make all fourteen rows identical across baseline/candidate runs.
3. Record actual source hashes and local/queued-only call paths in a new `${H}.actual-source-audit.md`. The original D audit is supporting history, **not** a sandbox or a substitute for this new-source review. An unsafe/unverified path is BLOCKED before boot.
4. Verify only the new test changed since checkpoint with `ownership`; source/drafts/protected inputs remain unchanged. Keep all shared helpers untouched.

- [ ] **Step 3: Build current production and run the honest baseline characterization.**

After the actual-source audit, use the common preamble, actual H, timeout0, and sequential calls:

```bash
nav_record orbite-history-density-new-test-lint test_command bundle exec rubocop test/system/orbite_history_density_test.rb || exit $?
nav_record orbite-history-density-baseline-build rails_test tailwindcss:build || exit $?
nav_record orbite-history-density-baseline-inputs python3 "$E/orbite-history-density-state-v1.py" create "${H}.baseline-inputs.json" || exit $?
nav_record orbite-history-density-baseline browser_test test/system/orbite_history_density_test.rb -n /density_characterization/ || exit $?
nav_record orbite-history-density-baseline-ownership python3 "$E/orbite-history-density-state-v1.py" ownership "${H}.checkpoint.json" || exit $?
```

Expected: characterization **PASS**, exactly one test with eight recorded real contexts (EN/FR × light/dark × inline1400×1000/modal375×812), fourteen rows, overflow sufficient to avoid a capped two-row sample. Record actual panel/content/list/each-row rectangles, title/account/date/datetime/order/IDs and complete-row counts. Preserve original JSONLs/screenshots and baseline new-test SHA256. Open representative baseline inline/modal screenshots. This PASS establishes the baseline; it is not a manufactured RED or the v3 mockup's 6/7 count. If it errors/fails, stop before production changes.

- [ ] **Step 4: Add request design contracts and run meaningful request/native RED.**

In `test/integration/orbite_shell_test.rb`, inside each existing locale loop's lean-History test, replace only the obsolete account paragraph assertions:

```diff
-          assert_select "p > span", count: 0
-          assert_select "p", text: @chat.account.name, count: 1
+          assert_select "a > .n-chat-history-title", text: "What are the key findings in this report?", count: 1
+          assert_select "a > .n-chat-history-meta.n-workspace-help > .n-chat-history-account", text: @chat.account.name, count: 1
+          assert_select "div > p", count: 0
```

Add these **two tests inside that same `%i[en fr]` loop**, before the rail-navigation test. Keep all existing close/delete/naming/privacy contracts:

```ruby
    test "density chrome preserves accessible History boundaries in #{locale}" do
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "#chat-history[aria-labelledby=chat-history-title]", count: 1 do
        assert_select "h2#chat-history-title.sr-only", text: I18n.t("nosia.orbite.navigation", locale: locale), count: 1
        assert_select "[data-orbite-history]", count: 1 do |sections|
          assert_equal I18n.t("nosia.chat_workspace.history_title", locale: locale), sections.first["aria-label"]
          assert_select "h3, .n-orbite-history-heading", count: 0
          assert_select "p:not([data-history-empty])", count: 0
        end
        assert_select "#workspace-navigation-close", count: 1
        assert_select ".n-orbite-panel-links a", minimum: 1
      end
      @user.account_users.destroy_all
      get new_chat_path, headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "[data-orbite-history] [data-history-empty]", text: I18n.t("nosia.chat_workspace.no_history", locale: locale), count: 1
    end

    test "density labels retain full bounded title and escaped account attributes in #{locale}" do
      question = workspace(:messages, :workspace_question)
      question.update_columns(content: "A" * 240)
      dangerous = %q{Research "quoted" & <img src=x onerror="alert(1)"> <script>bad()</script>}
      @second.update_columns(name: dangerous)
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      preview = "A" * 119 + "…"
      assert_select "[data-history-chat='#{@chat.id}']", count: 1 do |rows|
        row = rows.first
        assert_select "a > .n-chat-history-title, a > .n-chat-history-meta > .n-chat-history-account", count: 2
        link = row.at_css("div > a")
        assert_equal preview, link["title"]
        assert_equal preview, link.at_css(".n-chat-history-title").text
        assert_equal 120, link.at_css(".n-chat-history-title").text.length
        account = link.at_css(".n-chat-history-account")
        assert_equal dangerous, account.text
        assert_equal dangerous, account["title"]
        assert_includes link.text, preview
        assert_includes link.text, dangerous
        assert_empty row.css("img, script, [onerror]")
        time = link.at_css("time")
        assert_equal @chat.updated_at.iso8601, time["datetime"]
        assert_equal I18n.l(@chat.updated_at, format: :short, locale: locale), time.text
        assert_select "form[action='#{chat_path(@chat)}'] input[name=_method][value=delete]", count: 1
      end
      assert_select ".n-chat-header h1", text: preview
      assert_equal "A" * 240, question.reload.content
    end
```

The parsed escaping test asserts new spans exist before dereferencing them, so baseline produces a meaningful assertion failure rather than nil-method ERROR. Browser-only `:scope` remains in native JavaScript; request selectors use the existing assert-select context rather than depending on Nokogiri `:scope` semantics.

Before executing these newly changed requests, read their **actual complete patched source** and append its hash/local call-path audit to `${H}.actual-source-audit.md`: plain fixture `update_columns`, membership removal, authenticated local GET, parsing/escaping only; inherited fixture/test adapter still unchanged. No provider/generation/job execution, upload/URL registration, or hidden helper alteration may be inferred safe merely from this plan's intended code.

With common preamble/actual H:

```bash
if nav_record orbite-history-density-request-red rails_test test test/integration/orbite_shell_test.rb -n /density_/; then
  exit 125
else
  red_exit=$?
fi
test "$red_exit" -eq 1 || exit "$red_exit"
```

Read the complete raw log before continuing: expected four request tests, assertion failures for old visible History chrome/missing full-value spans/attributes, **zero errors/skips**. Nil selector, boot/auth/fixture errors are BLOCKED, not design RED.

Then in a separate foreground call:

```bash
if nav_record orbite-history-density-native-red browser_test test/system/orbite_history_density_test.rb -n /native_design_/; then
  exit 125
else
  red_exit=$?
fi
test "$red_exit" -eq 1 || exit "$red_exit"
```

Expected: two native assertion failures, one for visible `h3`/help and one for old below-body trash/single-line styling; no boot/JS errors/skips. `density_row` has old-markup fallbacks specifically to measure the existing row without a null-node fake RED. Preserve logs and initial failed screenshots. The parent conditionally authorizes the implementer to proceed only after actually inspecting the completed baseline and both meaningful RED receipts; return BLOCKED instead if any intended prerequisite is not established. No interim approval request is required for the expected results.

- [ ] **Step 5: Implement the minimal ERB/CSS change.**

Replace `app/views/chats/_history_items.html.erb` with:

```erb
<%# locals: (chat:, conversations:, titles:) %>
<% if conversations.any? %>
  <ul class="n-chat-history-list !list-none">
    <% conversations.each do |conversation| %>
      <li class="n-chat-history-row" data-history-chat="<%= conversation.id %>">
        <div>
          <% title = chat_workspace_title(conversation, titles: titles) %>
          <%= link_to chat_path(conversation), class: "n-workspace-link", title: title,
            aria: { current: conversation == chat ? "page" : nil } do %>
            <span class="n-chat-history-title"><%= title %></span>
            <span class="n-chat-history-meta n-workspace-help">
              <span class="n-chat-history-account" title="<%= conversation.account.name %>"><%= conversation.account.name %></span>
              <time datetime="<%= conversation.updated_at.iso8601 %>"><%= l(conversation.updated_at, format: :short) %></time>
            </span>
          <% end %>
        </div>
        <%= button_to chat_path(conversation), method: :delete,
          class: "n-workspace-button n-workspace-danger n-chat-history-delete",
          aria: { label: t("nosia.nav.delete_chat") }, title: t("nosia.nav.delete_chat"),
          data: { turbo_confirm: t("nosia.actions.confirm_delete") } do %>
          <%= inline_svg "svg/trash-bin.svg", aria_hidden: true, class: "h-5 w-5" %>
        <% end %>
      </li>
    <% end %>
  </ul>
<% else %>
  <p class="n-workspace-help" data-history-empty><%= t("nosia.chat_workspace.no_history") %></p>
<% end %>
```

The trash block/empty state are copied byte-for-byte. No `html_safe`, manually shortened string, new locale, or client state. In `app/views/application/_orbite_shell.html.erb`, delete **only**:

```diff
-          <h3 class="n-orbite-history-heading"><%= t("nosia.chat_workspace.history_title") %></h3>
```

Replace `app/assets/stylesheets/nosia/orbite_chat.css:48–53` only with:

```css
.n-orbite-shell .n-chat-history-list { margin-top: 0; }
.n-orbite-shell .n-chat-history-row { display: grid; grid-template-columns: minmax(0, 1fr) 44px; align-items: center; border-color: var(--orbite-line); padding-block: 3px; gap: 4px; }
.n-orbite-shell .n-chat-history-row > div { min-width: 0; }
.n-orbite-shell .n-chat-history-row .n-workspace-link { display: block; min-width: 0; min-height: 44px; padding: 8px; color: var(--orbite-text); text-decoration: none; }
.n-orbite-shell .n-chat-history-row .n-workspace-link:hover { background: var(--orbite-bubble); border-radius: .375rem; }
.n-orbite-shell .n-chat-history-row [aria-current=page] { background: var(--orbite-bubble); border-radius: .375rem; box-shadow: inset 2px 0 var(--orbite-accent); }
.n-orbite-shell .n-chat-history-row :is(.n-chat-history-title, .n-chat-history-account) { display: block; min-width: 0; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.n-orbite-shell .n-chat-history-row .n-chat-history-meta { display: flex; flex-wrap: wrap; align-items: baseline; gap: 0 .375rem; min-width: 0; margin-top: 3px; color: var(--orbite-muted); font-size: .75rem; line-height: 1.625; font-weight: 400; }
.n-orbite-shell .n-chat-history-row .n-chat-history-account { flex: 1 1 4rem; }
.n-orbite-shell .n-chat-history-row time { display: block; flex: 0 0 auto; min-width: 0; max-width: 100%; white-space: normal; overflow-wrap: anywhere; }
.n-orbite-shell .n-chat-history-delete { display: inline-flex; align-items: center; justify-content: center; width: 44px; min-width: 44px; min-height: 44px; padding: .5rem; color: var(--orbite-text); }
.n-orbite-shell .n-chat-history-row form { justify-self: end; }
```

This preserves inherited link font/weight, current-title bold, colors, focus rules and responsive panel dimensions. It removes the inherited whole-link underline so metadata is not underlined, and keeps metadata normal-weight as in the selected prototype. The date's intrinsic width is reserved where possible; flex wrapping permits its own line without clipping. Only title/account have ellipsis. Hover changes no dimensions. Do not modify adjacent composer/reader CSS.

In `app/assets/stylesheets/nosia/orbite_shell.css`, delete only the two obsolete rules:

```diff
-.n-orbite-shell .n-orbite-navigation[data-inline=true] .n-chat-history-row { display: grid; grid-template-columns: minmax(0, 1fr); }
-.n-orbite-history-heading { font-size: .875rem; font-weight: 600; }
```

They are nonadjacent (original113/116); preserve every intervening rule.

- [ ] **Step 6: Migrate only superseded existing title/account visual contracts.**

In `test/controllers/chat_workspace_test.rb` change only the History selector in the existing bounded-title test:

```diff
-    assert_select "[data-history-chat='#{@chat.id}'] a[aria-current=page]", text: "#{'A' * 119}…", count: 1
+    assert_select "[data-history-chat='#{@chat.id}'] a[aria-current=page] > .n-chat-history-title", text: "#{'A' * 119}…", count: 1
```

In `test/system/orbite_workspace_test.rb`, retain all eight existing cases (`539–604`), the locale/new/saved/theme product, fixture labels, min-eight-actual-font-em width guard, 240px panel, native controls, current padding/aria, deletion/source/privacy guards, zero document scrolling, and forward/reverse trusted traversal. Apply these exact local replacements:

```diff
-        assert geometry.fetch("textFits"), geometry.to_json
+        assert geometry.fetch("labelsFit"), geometry.to_json
+        assert geometry.fetch("dateFits"), geometry.to_json
+        assert_equal title, geometry.fetch("titleText")
+        assert_equal title, geometry.fetch("nativeTitle")
+        assert_equal conversation.account.name, geometry.fetch("accountText")
+        assert_equal conversation.account.name, geometry.fetch("nativeAccount")
+        assert_operator geometry.fetch("link").fetch("height"), :>=, 44, geometry.to_json
-        assert_selector "#{row} > div > a", text: title, exact_text: true
-        assert_selector "#{row} > div > p", text: conversation.account.name, exact_text: true
+        assert_selector "#{row} > div > a > .n-chat-history-title", text: title, exact_text: true
+        assert_equal conversation.account.name, page.evaluate_script("document.querySelector(arguments[0]).textContent", "#{row} .n-chat-history-account")
-        assert_no_selector "#{row} > div > p > span", visible: :all
+        assert_no_selector "#{row} > div > p", visible: :all
```

Replace only `orbite_history_rows` (original677–701) with:

```ruby
    def orbite_history_rows
      page.evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector('#chat-history'), content = panel.querySelector('.n-orbite-panel-content')
          const rect = node => node.getBoundingClientRect().toJSON()
          return { panel: rect(panel), clientWidth: content.clientWidth, scrollWidth: content.scrollWidth,
            rows: [...panel.querySelectorAll('[data-history-chat]')].map(row => {
              const body = row.querySelector(':scope > div'), link = body.querySelector('a')
              const form = row.querySelector('form'), button = form.querySelector('button'), b = rect(body), f = rect(form)
              const title = link.querySelector('.n-chat-history-title'), account = link.querySelector('.n-chat-history-account')
              const time = link.querySelector('time'), l = rect(link), t = rect(time), style = getComputedStyle(link)
              const labelsFit = [title, account].every(node => {
                const s = getComputedStyle(node), box = rect(node)
                return box.width > 0 && box.left >= l.left && box.right <= l.right && box.top >= l.top && box.bottom <= l.bottom &&
                  s.whiteSpace === 'nowrap' && s.overflowX === 'hidden' && s.textOverflow === 'ellipsis' &&
                  box.height <= parseFloat(s.lineHeight) + 1
              })
              const range = document.createRange(); range.selectNodeContents(time)
              const dateFits = getComputedStyle(time).textOverflow !== 'ellipsis' &&
                t.left >= l.left && t.right <= l.right && t.top >= l.top && t.bottom <= l.bottom &&
                [...range.getClientRects()].every(line => line.left >= t.left - 1 && line.right <= t.right + 1 && line.top >= t.top - 1 && line.bottom <= t.bottom + 1)
              return { id: row.dataset.historyChat, row: rect(row), body: b, link: l, form: f, button: rect(button),
                paddingInlineStart: parseFloat(style.paddingInlineStart), paddingInlineEnd: parseFloat(style.paddingInlineEnd),
                paddingBlockStart: parseFloat(style.paddingBlockStart), paddingBlockEnd: parseFloat(style.paddingBlockEnd),
                textInset: rect(title).left - l.left, fontSize: parseFloat(style.fontSize), labelsFit, dateFits,
                titleText: title.textContent, accountText: account.textContent,
                nativeTitle: link.title, nativeAccount: account.title,
                separateAction: f.left >= b.right && f.top < b.bottom && f.bottom > b.top }
            }) }
        })()
      JS
    end
```

Do **not** Range-assert clipped title/account text fits its box: invisible glyph ranges exceed it by design. Only full DOM/native-title and single-line boxes/CSS apply to those two labels. Keep Range containment for the untruncated semantic date. Leave `orbite_history_tab_to` (original703–712), all other private helpers and every non-History case byte-identical.

- [ ] **Step 7: Build candidate, freeze complete inputs, then focused GREEN and after-characterization.**

Audit actual modified/new source once more. With common preamble/actual H:

```bash
nav_record orbite-history-density-candidate-build rails_test tailwindcss:build || exit $?
nav_record orbite-history-density-candidate-freeze python3 "$E/orbite-history-density-state-v1.py" create "${H}.tested.json" || exit $?
nav_record orbite-history-density-request-green rails_test test test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb || exit $?
nav_record orbite-history-density-native-green browser_test test/system/orbite_history_density_test.rb -n /native_design_/ || exit $?
nav_record orbite-history-density-candidate browser_test test/system/orbite_history_density_test.rb -n /density_characterization/ || exit $?
nav_record orbite-history-density-green-freeze python3 "$E/orbite-history-density-state-v1.py" check "${H}.tested.json" || exit $?
```

Expected: all0, zero F/E/S; unchanged characterization/sample source SHA; eight new characterization originals. No source/test edits after this freeze; an authorized correction invalidates and reruns affected gates with a new freeze. Baseline and candidate execute at the same actual precommit HEAD with distinct frozen working-tree hashes; the recorded HEAD alone is not a candidate-byte identity.

Create external `$E/orbite-history-density-compare-v1.py` with the patch tool:

```python
import hashlib
import json
from pathlib import Path
import re
import sys

def samples(logname):
    log = Path(logname)
    assert int(log.with_name(log.name.replace('.raw.log', '.TRUE.exit')).read_text()) == 0
    paths = set(re.findall(r'Orbite measurements: ([^\r\n]+)', log.read_text()))
    found = {}
    for name in paths:
        path = Path(name)
        assert path.is_file() and not path.is_symlink()
        for number, line in enumerate(path.read_text().splitlines(), 1):
            item = json.loads(line)
            if not item.get('label', '').startswith('history-density-characterization-'):
                continue
            s = item['sample']
            key = (item['locale'], item['theme'], tuple(s['viewport']), s['mode'])
            assert key not in found, key
            found[key] = (s, {'path': name, 'line': number,
                              'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                              'sourceCommit': item['sourceCommit']})
    assert len(found) == 8, len(found)
    return found

before, after = samples(sys.argv[1]), samples(sys.argv[2])
baseline_freeze = json.loads(Path(sys.argv[4]).read_text())
candidate_freeze = json.loads(Path(sys.argv[5]).read_text())
test_name = 'test/system/orbite_history_density_test.rb'
assert baseline_freeze['files'][test_name] == candidate_freeze['files'][test_name], 'Permanent characterization source changed'
assert before.keys() == after.keys()
results = []
for key in sorted(before):
    b, br = before[key]
    a, ar = after[key]
    assert b['version'] == a['version'] == 1
    assert b['scrollTop'] == a['scrollTop'] == 0
    for part in ('panel', 'content'):
        for dimension in ('width', 'height'):
            assert abs(b[part][dimension] - a[part][dimension]) <= 1, (key, part, dimension)
    semantic = lambda s: [{k: r[k] for k in ('id', 'title', 'account', 'date', 'datetime')} for r in s['rows']]
    assert semantic(b) == semantic(a)
    assert len(b['rows']) == len(a['rows']) == 14
    assert b['fullyVisible'] < a['fullyVisible'] < 14, (key, b['fullyVisible'], a['fullyVisible'])
    results.append({'context': key, 'baselineCount': b['fullyVisible'], 'candidateCount': a['fullyVisible'],
                    'baseline': br, 'candidate': ar, 'baselineSample': b, 'candidateSample': a})
with Path(sys.argv[3]).open('x') as output:
    json.dump({'result': 'PASS strictly more complete rows in both real modes in every locale/theme',
               'comparisons': results}, output, indent=2)
print(json.dumps(results, indent=2))
```

Run with the **actual** baseline and candidate `.raw.log` paths as arguments, not their stem guesses:

```bash
nav_record orbite-history-density-count-comparison python3 "$E/orbite-history-density-compare-v1.py" "$baseline_raw" "$candidate_raw" "${H}.density-comparison.json" "${H}.baseline-inputs.json" "${H}.tested.json" || exit $?
```

Assign `baseline_raw`/`candidate_raw` to the two actual recorded paths in that shell after the common preamble. Expected: comparison0 and strict improvement for all eight contexts, panel/content dimensions unchanged within1px, identical fourteen semantic rows. If dimensions/sample semantics differ or candidate does not improve, return BLOCKED with both originals; no mockup substitution, smaller controls/type, fixture tweaking between runs, or fabricated density claim.

- [ ] **Step 8: Run complete implementation regression gates and actual four-Ruby lint.**

With common preamble/actual H, timeout0, one completed call at a time:

```bash
nav_record orbite-history-density-full-native browser_test test/system/orbite_history_density_test.rb test/system/orbite_workspace_test.rb test/system/orbite_navigation_refinements_test.rb test/system/chat_workspace_test.rb test/system/compact_headers_test.rb test/system/chat_refresh_draft_test.rb || exit $?
nav_record orbite-history-density-localization browser_test test/system/localization_test.rb || exit $?
nav_record orbite-history-density-lint test_command bundle exec rubocop test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb test/system/orbite_workspace_test.rb test/system/orbite_history_density_test.rb || exit $?
nav_record orbite-history-density-owned-check python3 "$E/orbite-history-density-state-v1.py" ownership "${H}.checkpoint.json" || exit $?
nav_record orbite-history-density-tested-check python3 "$E/orbite-history-density-state-v1.py" check "${H}.tested.json" || exit $?
git diff --check
```

Expected: all0/nonzero real counts, zero F/E/S. Whole **six** native files, not a reader/compact subset. Native deletion cancel/confirm, root/member/nonmember/child isolation and source protections still run unchanged. Existing labels such as `click_link "First account question"` must work through full DOM text/native title; do not silently edit those callers to rescue a failed selection. This task does not repeat unrelated seven-workspace/final48 gates; Task 2 does.

Read actual geometry/contrast/native records and open original screenshots: baseline/candidate inline/modal; long spaced/unspaced account/title at narrow/wide; FR dark; short landscape; focused link/trash/Close; actual opened full question and Usage account. Verify actual 4.5:1 text, 3:1 icon/focus, 2px focus, five-point hits, positive widths, actual long overflow versus fitting short labels, complete dates, all44px, active padding, no horizontal/root scroll. Record exactly which originals were opened, hashes and observations; do not claim native tooltip UI, physical touch, screen-reader or native zoom testing. Sources/Formatting/Stop/reader80px/paused1px/own-success follow are established by unchanged-source checks and whole regressions, not the new list sampler alone.

- [ ] **Step 9: Freeze tested patch/blob identity, commit exactly eight paths, then independent SPEC → QUALITY.**

Before staging, inspect complete diff and nonowned/draft checks. The parent conditionally authorizes this exact scoped commit only after every prescribed gate and implementer self-review is green; do not include spec/plan/dirty docs in it. An unexpected failure or preservation mismatch returns BLOCKED without staging/commit. With common preamble/actual H:

```bash
nav_record orbite-history-density-precommit-freeze python3 "$E/orbite-history-density-state-v1.py" check "${H}.tested.json" || exit $?
git diff --check
git add -- app/views/chats/_history_items.html.erb app/views/application/_orbite_shell.html.erb app/assets/stylesheets/nosia/orbite_chat.css app/assets/stylesheets/nosia/orbite_shell.css test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb test/system/orbite_workspace_test.rb test/system/orbite_history_density_test.rb || exit $?
nav_record orbite-history-density-staged-identity python3 "$E/orbite-history-density-state-v1.py" staged "${H}.tested.json" "${H}.tested-eight-path.patch" || exit $?
git diff --cached --stat
git commit -m "feat(ui): Increase Orbite History density with compact labels" || exit $?
nav_record orbite-history-density-commit-identity python3 "$E/orbite-history-density-state-v1.py" committed "${H}.tested.json" || exit $?
git status --short
```

Expected: exactly eight committed paths and identical tested blobs; five D draft hashes untouched, parent spec/plan untouched; no app/config/helper/JS/fixture changes outside scope. Record the actual precommit execution HEAD plus frozen tested files and actual resulting commit—not a claim that tests executed at the future SHA. Write a unique task report/index with actual RED/GREEN/baseline counts/comparison, all commands/true exits, semantic/current/native evidence, preservation proofs and limitations. Use no automatic D or integration commit.

Parent dispatches a **fresh independent SPEC reviewer**, then only after approval a **different fresh QUALITY reviewer**, both read-only/no runtime by default, against approved spec, exact eight-path diff and actual artifacts. Report fixes as new bounded test-first work and refresh affected freezes/gates; no “accepted” Important/Critical finding without correction/review. Do not start Task 2 until History SPEC → QUALITY is accepted.

## Task 2: Reconcile the pending D drafts and refresh final current-source evidence

**Owner:** A separate fresh implementer, only the five D docs. Do not blindly resume/recreate the old owner's drafts. Its report is READY_FOR_REVIEW at f487607; old640/154993/security results become **historical** after Task 1. No application/test/config/helper/script-source edits during final gates. External new evidence scripts are allowed, uniquely named; original evidence is immutable. Return docs **UNSTAGED** for parent audit, fresh D SPEC → QUALITY and independent whole-feature review. No automatic five-doc commit.

- [ ] **Step 1: Read the actual latest drafts and reconcile only the current History contract.**

Read all five files in full plus their actual current diffs, History SPEC/QUALITY outcomes, old refinement plan Task D (`1651–1991`), actual D report/manifest/receipts and original selected logs. Recheck Task 1's preservation hashes first. Keep its reserved composer/reader, first-question120 bound, membership/private-root, native draft/PDF/Stop/worker-authority, uncached freshness, source, historical results and narrow Turbo-focus race text.

Use patch edits with these exact current-content changes (line numbers are planning-time references; do not replace whole drafts from an older listing):

1. In `docs/orbite-workspace.md`, after “Expansion is temporary page state, not a persisted preference.” add:

```markdown
History uses compact editorial rows with a separate trash action. Its visible
History heading and introductory help are removed; the hidden Navigation heading,
localized History section label, empty guidance, mobile links, and Close remain.
Titles and account names are one-line previews with CSS ellipsis only on overflow.
Their complete existing display strings remain in the link DOM and native `title`
attributes; activating the ordinary conversation link exposes the original
question in the wrapping transcript and full account under Usage. Toolbar previews
remain compact. The display-title helper's
existing 120-character bound is unchanged. Dates remain semantic and complete,
sharing metadata space when possible or wrapping below the account without
ellipsis. Inline width remains 240px, with padded active links and separate
at-least-44px actions; density does not come from smaller text or controls.
```

Replace its current safe-recipe paragraph with:

```markdown
The approved [History density amendment](superpowers/specs/2026-10-31-orbite-history-density-design.md)
adds compact one-line labels without changing reader/composer ownership.
The current safe execution recipe is **Task 2** of the
[History density plan](superpowers/plans/2026-10-31-orbite-history-density.md),
not the unrestricted historical composer commands or pre-density final results.
```

Change heading `### 2026-10-31 selected verification` to `### Historical selected verification — before History density` and prepend “Before the History density amendment, ” to the paragraph beginning “At application/test source `f487607...`”. Keep all old counts/warning/exits and provenance **unchanged**, explicitly historical. Append the new verified section only after fresh gates (Step7).

2. In `docs/chat-workspace.md`, replace the paragraph starting “The panel keeps its visually hidden…” with:

```markdown
The panel keeps its visually hidden localized Navigation heading and History
section label, without a duplicate logo, visible History heading, or introductory
help. Title and account previews occupy one line with CSS ellipsis on overflow;
full existing display values remain in DOM/native `title` attributes. Open the
ordinary conversation link to read the original question and full Usage account
without relying on pointer hover. Existing toolbar previews remain compact. The 120-character display-title
bound is unchanged; dates stay complete and may wrap onto a metadata line of
their own. The 240px inline panel, padded active link, separate at-least-44px
Cross/Trash targets, native focus/dismissal, and confirmed deletion are retained.
```

Replace only its current plan link/recipe reference with:

```markdown
Use the dedicated isolated test environment and sequential suite commands in the
[History density plan, Task 2](superpowers/plans/2026-10-31-orbite-history-density.md),
without live providers or workers. Keep actual exits/counts, screenshot states,
contrast samples, and baseline differences in the execution evidence—not inferred passes.
```

3. In `docs/chat-composer.md`, replace the current Task D recipe link with:

```markdown
The current selection is **Task 2** of the
[History density plan](superpowers/plans/2026-10-31-orbite-history-density.md).
```

After the Dedicated chat-page shell's navigation-refinement paragraph add:

```markdown
The [History density amendment](superpowers/specs/2026-10-31-orbite-history-density-design.md)
changes only History ERB/scoped CSS and coupled tests. Compact title/account
previews recover their full existing display values through ordinary conversation
navigation; dates and native confirmed deletion remain intact. It does not alter
the reserved dock, native Formatting, source coordination, Stop, or draft handoff.
Earlier selected results remain dated historical evidence.
```

4. In `docs/compact-headers.md`, insert immediately before “The following sections retain…” in its opening supersession notice:

```markdown
The [History density amendment](superpowers/specs/2026-10-31-orbite-history-density-design.md)
also replaces wrapping History title/account labels with single-line CSS previews,
retaining full existing DOM/native-title values and ordinary transcript/Usage access.
Dates, native controls, and the retained reader safeguards are not superseded.
```

5. In `docs/README.md`, change only the Orbite guide's description:

```diff
-- [Orbite workspace](orbite-workspace.md) — shared rail, responsive private history, reading surface, and reserved native composer.
+- [Orbite workspace](orbite-workspace.md) — shared rail, compact private History previews, reading surface, and reserved native composer.
```

No fabricated product RED for docs. Static truth/link checks plus the actual fresh final gates below apply. Preserve all original draft/evidence bytes in the Task 1 checkpoint and old D snapshot.

- [ ] **Step 2: Refresh actual final-source safety audit, historical receipt provenance, and dynamic freeze.**

Read the **actual new test source and all inherited helpers/adapters again**, the modified test source, all selected entrypoints and source actions referenced by the D audit. Verify same isolated local/test-queue path; explicitly audit callback-free12+12 inserts, local native link activation, real PDF bytes, source/freshness/account/Stop/Retry behavior and queued-only localized accounting callbacks. No helper-bound dummy key is a network sandbox. Parent-approved baseline provenance need not be reauthorized; it must still be rehashed.

Use the dynamic utility from this plan, not old scripts hardcoding f487607. Reserve a new D prefix (record it and assign that actual path in later shells):

```bash
HD="$(mktemp "$E/orbite-history-density-final-D.XXXXXX")" || exit $?
nav_record orbite-history-density-final-build rails_test tailwindcss:build || exit $?
nav_record orbite-history-density-final-freeze python3 "$E/orbite-history-density-state-v1.py" create "${HD}.tested.json" || exit $?
```

Expected: build0; complete current runtime/test/fixture/config/library/vendor/bin inputs plus docs/newtest frozen; current HEAD is the actual accepted History implementation commit (possibly with parent-owned spec/plan-only descendants). Confirm unchanged all238 protected/ten installed/helper/recorder/form and all production JavaScript. No actual runtime source edits after freeze.

The old D final receipt's `artifactSHA256` map is relative to E. Create a **new** external `$E/orbite-history-density-old-D-audit-v1.py` with:

```python
import hashlib
import json
from pathlib import Path
import sys

E = Path('/tmp/opencode/chat-workspace-recovery-Pbwj0x')
receipt = json.loads((E / 'orbite-refinement-D-final-receipt.json').read_text())
checked = {}
for name, digest in receipt['artifactSHA256'].items():
    rel = Path(name)
    assert not rel.is_absolute() and '..' not in rel.parts
    path = E / rel
    assert path.is_file() and not path.is_symlink(), name
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    assert actual == digest, (str(path), actual, digest)
    checked[str(path)] = actual
with Path(sys.argv[1]).open('x') as output:
    json.dump({'scope': 'Historical D artifact integrity; not current runtime acceptance',
               'head': receipt['head'], 'artifactSHA256': checked}, output, indent=2)
print('PASS original D artifacts resolved relative to E; no old result relabelled current')
```

Run with common preamble/actual HD:

```bash
nav_record orbite-history-density-old-D-audit python3 "$E/orbite-history-density-old-D-audit-v1.py" "${HD}.historical-D-audit.json" || exit $?
```

A real mismatch/missing original is BLOCKED and preserved, not repaired by rewriting historical artifacts. The parent had identified an offline path-resolution bug; resolving relative E corrects that audit, not source or provenance.

- [ ] **Step 3: Run all actual final48 whole-file selections sequentially.**

Common preamble/actual HD, timeout0, inspect complete raw output and true exit before each next call. These are the exact original final47 selections plus the new density file, **26 focused / 9 chat / 7 workspaces / 6 navigation**:

```bash
nav_record orbite-history-density-final-focused rails_test test test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_tools_test.rb test/controllers/chat_account_citations_test.rb test/controllers/chat_account_url_race_test.rb test/controllers/chat_sources_controller_test.rb test/models/chat_test.rb test/models/dashboard_recents_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/profiles_controller_test.rb test/internationalization/catalogs_test.rb test/integration/token_footer_test.rb || exit $?
nav_record orbite-history-density-final-chat browser_test test/system/orbite_history_density_test.rb test/system/orbite_workspace_test.rb test/system/orbite_navigation_refinements_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_workspace_layout_test.rb test/system/chat_refresh_draft_test.rb || exit $?
nav_record orbite-history-density-final-workspaces browser_test test/system/dashboard_test.rb test/system/accounts_settings_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/mcp_workspace_test.rb test/system/profile_management_test.rb || exit $?
nav_record orbite-history-density-final-navigation browser_test test/system/localization_test.rb test/system/color_theme_test.rb test/system/account_experience_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/system/sources_workspace_upload_test.rb || exit $?
```

Expected each0/zero F/E/S and actual nonzero counts/seeds/assertions; do not predict/reuse old640/154993. Retain unsuppressed MCP duplicate-key warning debt and compare the actual timestamp-normalized warning multiset with prior D; new warnings are not automatically waived. Native deletion confirmation/cancel, upload chooser/stored-PDF equality, private membership/source guards, uncached authoritative worker freshness, distinct-worker Stop/partial answer/unlock/eligible Retry, live localized totals, complete paused-reader80px/1px/Latest/own-submit behavior, same-full-URL native HTML/links/in-flight typing and source-bearing cancellation all remain whole-file gates. No narrowed reader/compact replacements or omitted refresh-draft file.

- [ ] **Step 4: Lint actual changed Ruby, seven JS syntax checks, source guards and local links.**

With common preamble/actual HD, generate the actual baseline-to-current Ruby selection including the new file; final lint is no longer “33 files” by assumption:

```bash
git diff --name-only --diff-filter=ACMR 7189d6de425122120f3fb4d7090d16a9ebb88f11 -- '*.rb' > "${HD}.changed-ruby.txt"
nav_record orbite-history-density-final-lint test_command bundle exec ruby -e 'files=File.readlines(ARGV.fetch(0),chomp:true); abort "No Ruby files" if files.empty?; abort "Missing new density test" unless files.include?("test/system/orbite_history_density_test.rb"); exec "bundle","exec","rubocop",*files' "${HD}.changed-ruby.txt" || exit $?
nav_record orbite-history-density-js-user-menu node --input-type=module --check < app/javascript/controllers/user_menu_controller.js || exit $?
nav_record orbite-history-density-js-navigation node --input-type=module --check < app/javascript/controllers/workspace_navigation_controller.js || exit $?
nav_record orbite-history-density-js-dialog node --input-type=module --check < app/javascript/controllers/chat_dialog_controller.js || exit $?
nav_record orbite-history-density-js-reader node --input-type=module --check < app/javascript/controllers/scroll_controller.js || exit $?
nav_record orbite-history-density-js-disclosures node --input-type=module --check < app/javascript/controllers/chat_disclosures_controller.js || exit $?
nav_record orbite-history-density-js-feedback node --input-type=module --check < app/javascript/controllers/chat_feedback_controller.js || exit $?
nav_record orbite-history-density-js-account node --input-type=module --check < app/javascript/controllers/chat_account_controller.js || exit $?
nav_record orbite-history-density-protected-JS git diff --exit-code f48760734132598ca0fdd9ca126f24cde8e36e24 -- app/javascript || exit $?
nav_record orbite-history-density-protected-reader git diff --exit-code 030e20ca42df7c0be66037f170b23594a3be38cf -- app/javascript/controllers/scroll_controller.js app/javascript/controllers/chat_disclosures_controller.js app/javascript/controllers/chat_dialog_controller.js app/javascript/controllers/chat_account_controller.js app/javascript/controllers/chat_feedback_controller.js app/views/chats/_token_totals.html.erb app/views/chats/new.html.erb app/views/chats/show.html.erb || exit $?
nav_record orbite-history-density-protected-backend git diff --exit-code 030e20ca42df7c0be66037f170b23594a3be38cf -- app/controllers app/models app/jobs config db Gemfile Gemfile.lock test/support/fixtures || exit $?
nav_record orbite-history-density-final-diffcheck git diff --check || exit $?
nav_record orbite-history-density-final-input-check python3 "$E/orbite-history-density-state-v1.py" check "${HD}.tested.json" || exit $?
nav_record orbite-history-density-final-links python3 "$E/orbite-refinement-D-links.py" "${HD}.links.json" || exit $?
```

The original D link script was statically read: no HEAD binding, exclusive output creation, safe local links/anchors only and no environment-file content reads. Reuse it read-only with a new output. It checks the five actual docs, including the new spec/plan links; do not assert its former62-link count. Inspect target/anchor truth and the final actual five-doc diff. Node is installed syntax-only; no Node build/install/dependency.

- [ ] **Step 5: Verify accepted NEW immutable7189 security provenance and scan NEW current source.**

Read `$E/orbite-task7-security-parent-review.md`, `$E/orbite-task7-security-recovery-report.md`, and `/tmp/opencode/orbite-task7-security-recompute-yj_gmyrs/{source-bindings.json,comparison.json}`. Parent independently accepted the user-authorized **NEW** baseline analysis. Do not re-ask recovery authorization, pretend the lost original JSON returned, scan an old current tree, or mutate/reuse a script asserting f487607 as current.

Create external `$E/orbite-history-density-security-v1.py` with the complete dynamic preflight/comparison below. Use a fresh unused suffix if needed:

```python
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path('/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui')
E = Path('/tmp/opencode/chat-workspace-recovery-Pbwj0x')
B = Path('/tmp/opencode/orbite-task7-security-recompute-yj_gmyrs')
EXPECTED = {'4fad3c218f35052d2f3a3eff4544480d05b60bc9199a001ec6242a8921b93ae3',
            'd84924377155b41e094acae7404ec2e521629d86f97b0ff628e3d1b263f8101c'}

def sha(path):
    path = Path(path)
    assert path.is_file() and not path.is_symlink(), str(path)
    assert not any(p == '.env' or p.startswith('.env.') for p in path.parts)
    return hashlib.sha256(path.read_bytes()).hexdigest()

mode, freeze_name = sys.argv[1:3]
assert Path.cwd() == ROOT
freeze = json.loads(Path(freeze_name).read_text())
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
assert head == freeze['head']
for name, info in freeze['files'].items():
    assert sha(ROOT / name) == info['sha256'], name
binding = json.loads((B / 'source-bindings.json').read_text())
assert binding['baseline'] == '7189d6de425122120f3fb4d7090d16a9ebb88f11'
assert len(binding['baseline_files']) == 1290
for name, info in binding['baseline_files'].items():
    if any(p == '.env' or p.startswith('.env.') for p in Path(name).parts):
        oid = subprocess.check_output(['git', 'rev-parse', binding['baseline'] + ':' + name], text=True).strip()
        assert oid == info['oid'], name
    else:
        assert sha(B / 'baseline-source' / name) == info['sha256'], name
assert sha(B / 'baseline-source.tar') == binding['archive_sha256']
assert binding['archive_sha256'] == 'b9d925bb244e3c970295f9d6c4b5f37f4be44a031b4f8cdcdff797506a77c55d'
lock = sha(ROOT / 'Gemfile.lock')
assert lock == binding['baseline_lock_sha256'] == '986f83c2ca94da7780c4a98eada046adb1e63fed8c9a63357986594dd66b8bd4'
for p in [ROOT / 'config/brakeman.yml', ROOT / 'config/brakeman.ignore',
          B / 'baseline-source/config/brakeman.yml', B / 'baseline-source/config/brakeman.ignore',
          Path.home() / '.brakeman/config.yml', Path('/etc/brakeman/config.yml')]:
    assert not p.exists() and not p.is_symlink(), str(p)
baseline_path = B / 'orbite-recomputed-baseline-security.json'
assert sha(baseline_path) == '59ef757700e7e6085e546eb5616c901e1768509e64a678bd62e2bced217b052c'
assert sha(E / 'orbite-task7-security-parent-review.md') == 'a0dc145c6915b7130ff228c7bcc6a65309f91a81a980ac5c065d10b42e02a209'
if mode == 'preflight':
    print(json.dumps({'head': head, 'baseline': binding['baseline'], 'baselineFiles': 1290,
                      'configParity': 'six recorded paths absent', 'lockSHA256': lock,
                      'result': 'PASS provenance only; no current scan yet'}, indent=2))
elif mode == 'compare':
    report, exit_file, output_file = map(Path, sys.argv[3:6])
    assert exit_file.read_text().strip() == '3'
    old = json.loads(baseline_path.read_text())
    new = json.loads(report.read_text())
    for scan in (old, new):
        assert scan['errors'] == [] and not scan.get('ignored_warnings')
        assert len(scan['warnings']) == 2
        assert {w['fingerprint'] for w in scan['warnings']} == EXPECTED
        for key, value in [('brakeman_version', '8.0.4'), ('ruby_version', '4.0.7'), ('rails_version', '8.0.5.1')]:
            assert scan['scan_info'][key] == value
        assert len(scan['scan_info']['checks_performed']) == 79
    assert new['scan_info']['checks_performed'] == old['scan_info']['checks_performed']
    assert new['warnings'] == old['warnings']
    result = {'head': head, 'scope': 'NEW current default full static scan; original baseline JSON remains LOST',
              'baselineReport': str(baseline_path), 'baselineReportSHA256': sha(baseline_path),
              'currentReport': str(report), 'currentReportSHA256': sha(report),
              'freeze': freeze_name, 'freezeSHA256': sha(freeze_name), 'trueScannerExit': 3,
              'exitFile': str(exit_file), 'warnings': new['warnings'], 'scanInfo': new['scan_info'],
              'errors': [], 'ignoredWarnings': [], 'added': [], 'removed': [],
              'result': 'PASS exact two known warnings/default79checks; not security-clean'}
    with output_file.open('x') as output:
        json.dump(result, output, indent=2)
    print(json.dumps(result, indent=2))
else:
    raise ValueError(mode)
```

The actual original archive is `baseline-source.tar` (statically inspected directory), not a guessed `baseline.tar`. A missing/changed archive/source/config/lock/review/report is BLOCKED, not permission to rebuild evidence. Environment-example basenames, if present in the binding, are checked by immutable Git object identity without reading/displaying/copying `.env*` contents. Other recorded extracted files are rehashed; this is provenance verification, not a baseline Rails boot.

Use common preamble/actual HD and timeout0:

```bash
nav_record orbite-history-density-security-inputs python3 "$E/orbite-history-density-security-v1.py" preflight "${HD}.tested.json" || exit $?
nav_record orbite-history-density-scanner-version test_command bundle exec brakeman --version || exit $?
security_marker="$(mktemp "$E/orbite-history-density-current-security.XXXXXX")" || exit $?
security="${security_marker}.report.json"
if nav_record orbite-history-density-current-security test_command bundle exec brakeman --path /home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui --format json --output "$security"; then
  security_exit=0
else
  security_exit=$?
fi
printf '%s\n' "$security_exit" > "${security_marker}.scanner.TRUE.exit"
test "$security_exit" -eq 3 || exit 125
nav_record orbite-history-density-security-comparison python3 "$E/orbite-history-density-security-v1.py" compare "${HD}.tested.json" "$security" "${security_marker}.scanner.TRUE.exit" "${HD}.security-comparison.json" || exit $?
nav_record orbite-history-density-postsecurity-freeze python3 "$E/orbite-history-density-state-v1.py" check "${HD}.tested.json" || exit $?
```

Expected installed8.0.4; true scanner3, parsedcomparison0, same two complete warning records/fingerprints, no additions/removals/errors/ignored warnings and same default79 checks/config/lock/dependencies. Inspect actual JSON and raw scanner output. No filters/fast/ignore/confidence changes, upgrade, no-exit switch, warning suppression, security-clean claim or reuse of f487607's current report. The original baseline report remains LOST; the independently accepted NEW immutable7189 scan is the comparison baseline.

- [ ] **Step 6: Inspect current original evidence and write append-only receipts/report.**

Create a uniquely named `${HD}.command-receipts.json` from the actual completed calls, with each exact invocation/raw/hash/TRUE.exit/hash/exit, current source HEAD and freeze. No predicted seeds/counts, filename-only evidence or “all screenshots reviewed” claim. Use the actual raw logs to discover original measurement JSONLs/PNGs; include sibling native traces not merely printed inventory (old C/P3 lesson). Rehash actual originals, parse sourceCommit/locale/theme/viewport and semantic geometry/native records. Open original representative screenshots with the image read tool, record path/hash/dimensions/observations individually, and retain actual full rows/line references for numeric assertions.

New `${HD}.report.md` and `${HD}.manifest.json` must contain:

- Approved design/spec and actual History commit; independent History SPEC→QUALITY outcomes; pending D/whole-feature reviews. Current precommit/frozen source identity and exact selected48 files, unchanged protected238, JS/reader/backend/source/fixture/native-owner boundaries, final source/test/config/doc hashes.
- Actual four group summaries/seeds/counts/assertions/F/E/S, build/lint actual Ruby selection/seven syntax/protection/link checks and true exits. Original f487607640/154993/33Ruby/security results explicitly historical. Old D artifact integrity checked relative E; no old receipt overwritten.
- Actual permanent characterization baseline/candidate comparison for all8 contexts, complete fourteen-row semantics and panel/content dimensions; actual strictly greater counts both modes. Link source/full120 preview/account native attributes, one-line spans, genuine overflow only for long labels, complete safe dates, separate44px actions, minimum8font-em content width/current padded aria, native Tab/Shift/Enter/Escape/five-point scrollport hits/outline2px, text4.5/icon-focus3 contrast, no root/horizontal scroll, full question/Usage account recovery. Record mockups separately as non-application evidence.
- Final whole-reader/composer/private/upload/Stop/freshness/accounting/draft coverage and retained80px/1px boundaries, reduced motion, single modal/focus owner, exact opener recovery/user popover/preferences. The old limit on same-frame Turbo focus remains narrow, not permission for a new failure.
- Actual current report/hash/source/version/config/default79 checks, baseline provenance/hash and true scanner3/comparison0; exact two warnings and no security-clean/certification claim. MCP JSON debt stays visible, with actual warnings classified, not suppressed.
- Original unknown/lost artifacts and D's two external parser failures remain preserved. NOT RUN: unrestricted unsafe suite, live providers/MCP/crawl/index/embeddings/workers, native browser zoom, screen reader, physical OS/mobile keyboard/native hover-tooltip UI. No user env/DEV-process/DB-lifecycle/dependency change, no automatic integration.

Evidence tooling errors are still nonzero/BLOCKED: retain originals and ask parent for a bounded corrected parser, not a retry hunt or false product RED. A source defect returns to a separately authorized test-first implementation and fresh History SPEC→QUALITY before new frozen final gates.

- [ ] **Step 7: Add only truthful fresh verification text, re-freeze docs, and return UNSTAGED.**

After real gates/inspection, generate the exact **new** verification section from actual originals, then append that generated text to `docs/orbite-workspace.md` with the patch tool. Create external `$E/orbite-history-density-summary-v1.py` with this complete code; it writes only new external files, not the guide:

```python
import hashlib
import json
from pathlib import Path
import re
import sys

E = Path('/tmp/opencode/chat-workspace-recovery-Pbwj0x')
prefix = Path(sys.argv[1])
density_path = Path(sys.argv[2])
freeze_path = Path(str(prefix) + '.tested.json')
freeze = json.loads(freeze_path.read_text())

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def gate(label, status=0):
    paths = list(E.glob(label + '.*.raw.log'))
    assert len(paths) == 1, (label, paths)
    path = paths[0]
    exit_path = path.with_name(path.name.replace('.raw.log', '.TRUE.exit'))
    assert int(exit_path.read_text()) == status, (label, exit_path.read_text())
    return {'label': label, 'raw': str(path), 'sha256': sha(path),
            'trueExitFile': str(exit_path), 'exitSHA256': sha(exit_path),
            'exit': status, 'text': path.read_text()}

groups = {}
for key in ('focused', 'chat', 'workspaces', 'navigation'):
    item = gate('orbite-history-density-final-' + key)
    matches = re.findall(r'(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips', item['text'])
    assert len(matches) == 1, item['raw']
    runs, assertions, failures, errors, skips = map(int, matches[0])
    assert runs > 0 and assertions > 0 and failures == errors == skips == 0
    seeds = re.findall(r'--seed (\d+)', item['text'])
    assert len(seeds) == 1, item['raw']
    item.update({'tests': runs, 'assertions': assertions, 'failures': failures,
                 'errors': errors, 'skips': skips, 'seed': int(seeds[0])})
    groups[key] = item
lint = gate('orbite-history-density-final-lint')
lint_matches = re.findall(r'(\d+) files? inspected', lint['text'])
assert len(lint_matches) == 1
lint_files = Path(str(prefix) + '.changed-ruby.txt').read_text().splitlines()
assert 'test/system/orbite_history_density_test.rb' in lint_files
assert len(lint_files) == int(lint_matches[0])
labels = ['orbite-history-density-final-build', 'orbite-history-density-protected-JS',
          'orbite-history-density-protected-reader', 'orbite-history-density-protected-backend',
          'orbite-history-density-final-links', 'orbite-history-density-security-comparison']
labels += ['orbite-history-density-js-' + x for x in
           ('user-menu', 'navigation', 'dialog', 'reader', 'disclosures', 'feedback', 'account')]
other = [gate(label) for label in labels]
scanner = gate('orbite-history-density-current-security', 3)
security = json.loads(Path(str(prefix) + '.security-comparison.json').read_text())
assert security['head'] == freeze['head'] and security['trueScannerExit'] == 3
assert len(security['warnings']) == 2
assert security['errors'] == security['ignoredWarnings'] == security['added'] == security['removed'] == []
density = json.loads(density_path.read_text())
assert len(density['comparisons']) == 8
density_words = []
for item in density['comparisons']:
    locale, theme, viewport, mode = item['context']
    before, after = item['baselineCount'], item['candidateCount']
    assert after > before
    density_words.append(f'{locale.upper()}/{theme} {mode} {viewport[0]}×{viewport[1]}: {before}→{after}')
group_words = ', '.join(f"{key} **{item['tests']} tests / {item['assertions']} assertions**" for key, item in groups.items())
footer = (
    '\n### 2026-10-31 History density selected verification\n\n'
    f"At frozen application/test source `{freeze['head']}`, the complete selected48\n"
    f'whole-file groups passed: {group_words}, with zero failures, errors, or skips\n'
    'and actual exit **0** for each group. The unchanged ordinary-sample native\n'
    'characterization measured strictly more fully visible rows in both modes:\n'
    + '; '.join(density_words) + '. These are real application measurements,\n'
    'not mockup counts. Complete sample semantics and panel/content dimensions\n'
    'were compared. Full DOM/native-title values, one-line previews, intact dates,\n'
    'ordinary transcript/Usage recovery and retained native protections were checked.\n\n'
    f'The build, RuboCop on **{len(lint_files)}** actual changed Ruby files, seven\n'
    'JavaScript syntax checks, protected-source checks, and local Markdown links\n'
    'exited **0**. The NEW current default Brakeman8.0.4 scan exited **3** with\n'
    'exactly the same two known warnings/no errors; comparison with the previously\n'
    'user-authorized NEW immutable7189 baseline exited **0**, with unchanged79\n'
    'checks and scanner inputs. The lost original JSON remains lost; this is not\n'
    'security certification or a security-clean claim. Existing MCP duplicate-key\n'
    'warnings remain unsuppressed debt. Current raw exits, seeds, geometry,\n'
    'contrast and actually inspected originals are retained in execution evidence.\n'
    'This footer follows the gates; execution of a future documentation commit is\n'
    'not implied. Unrestricted-suite, live-provider/worker, native zoom, screen-reader,\n'
    'physical mobile-keyboard and native hover-tooltip UI checks remain **NOT RUN**.\n'
    'Independent D/whole-feature review and separate commit authorization remain\n'
    'pending; this is not whole-feature approval or automatic integration.\n'
)
summary = {'head': freeze['head'], 'freeze': str(freeze_path), 'freezeSHA256': sha(freeze_path),
           'groups': groups, 'lint': lint, 'lintFiles': lint_files, 'otherGates': other,
           'scanner': scanner, 'security': security, 'density': density,
           'densityPath': str(density_path), 'densitySHA256': sha(density_path)}
with Path(str(prefix) + '.gate-summary.json').open('x') as output:
    json.dump(summary, output, indent=2)
with Path(str(prefix) + '.footer.md').open('x') as output:
    output.write(footer)
print(str(prefix) + '.gate-summary.json')
print(str(prefix) + '.footer.md')
```

With common preamble/actual HD, assign `density_comparison` to the actual Task1 comparison file (the reviewed `${H}.density-comparison.json`), then:

```bash
nav_record orbite-history-density-final-summary python3 "$E/orbite-history-density-summary-v1.py" "$HD" "$density_comparison" || exit $?
```

Expected0 and the actual summary/footer paths. Read the generated footer and original gate summaries, then append its complete text through a patch, preserving the historical pre-density section. Only append once. This is the only post-gate five-doc delta. Do not paste old640/154993, predicted mockup6/7 or fictional future values. The gate originals must uniquely match; ambiguity/missing/nonzero logs are BLOCKED rather than resolved by selecting the greenest result. Add exact completed invocations from the actual tool calls to the report's command ledger—the summary records real original logs, not a fabricated assertion that raw test logs printed their shell arguments.

With common preamble/actual HD:

```bash
nav_record orbite-history-density-postfooter-runtime python3 "$E/orbite-history-density-state-v1.py" check-runtime "${HD}.tested.json" || exit $?
nav_record orbite-history-density-postfooter-links python3 "$E/orbite-refinement-D-links.py" "${HD}.postfooter-links.json" || exit $?
nav_record orbite-history-density-postfooter-freeze python3 "$E/orbite-history-density-state-v1.py" create "${HD}.postfooter.json" || exit $?
nav_record orbite-history-density-postfooter-check python3 "$E/orbite-history-density-state-v1.py" check "${HD}.postfooter.json" || exit $?
git diff --check
git diff --stat
git diff --cached --name-only
git status --short
```

Expected all0, runtime unchanged; only planned guide footer after gates, exact five draft paths unstaged (plus separately identified parent-owned spec/plan metadata if still pending), empty index. The runtime-only check excludes five docs; independently compare exact doc hashes/diff to prove no other post-gate rewrite. Keep pre-footer and post-footer freezes separately; do not claim the original all-input freeze remains identical after editing a doc.

Return **READY_FOR_REVIEW, UNSTAGED** with actual prefix/receipts/report/manifest/security/geometry/original image paths and all limits. Parent audits actual original artifacts and five-doc patch, then dispatches fresh independent **D SPEC → D QUALITY**, then the required independent **whole-feature review** covering original Orbite, navigation refinements and History density. No automatic docs commit, stage, merge, push, PR, cleanup, or whole-feature approval. Only separate explicit parent/user authorization after those gates may permit a five-doc commit/integration.

## Coverage and handoff checklist

- [ ] EditorialA/no visible History `h3`/help; hidden Navigation/dialog/History section names, mobile links, empty state and independent Close retained (Task1 request/native RED→GREEN, full regression).
- [ ] Title/account at most one visual line, fitting short labels not forced to truncate, real long spaced/unspaced overflow, complete DOM/native title, existing120 helper unchanged and full-question/Usage-account native Enter recovery (Task1 full new matrix).
- [ ] Dates intact/time/ISO/localization, flexible metadata, no ellipsis/fixed clipping height; grid/min0/nonshrinking44px action, panel240/type sizes/padding/current aria, all native hit/focus/contrast/no-overlap/width guards retained (production scoped block + migrated/new native cases).
- [ ] Real before/after standalone unchanged characterization and external strict comparison, identical14 persisted roots/sample ordering/panels/viewports/ENFR/themes; no mockup thresholds (Task1 Steps2–7).
- [ ] Request parsed escaping/full120 and privacy/root/member/nonmember/child/deletion unchanged; only one actual History title assertion migration in controller test, eight coupled native cases/sampler, no other-test/helper/fixture edits (exact8path freeze/commit).
- [ ] All JS/reader/dock/source/formatting/Stop/accounting/authorization unchanged; source guards and whole6 implementation-native files plus localization, then complete final48; actual lint4 then actual baseline-changedRuby/seven syntax (Tasks1–2).
- [ ] Five original D drafts preserved throughout implementation, reconciled only after History SPEC→QUALITY; old results historical; NEW final security scan against accepted immutableNEW7189 provenance; old D artifact keys resolve relativeE (Task2).
- [ ] Fresh D SPEC→QUALITY, independent whole-feature review and separate explicit commit/integration decision remain pending after unstaged return. Execution choice is not reopened.

**Planning status:** Static source/spec/evidence reads only; no application, test, browser, database, build, lint or scanner execution is claimed by this plan. The parent performs the requested plan self-review before dispatching any implementer.

**Parent self-review:** Read the full plan against the approved specification and
actual source. Confirmed eight-path ownership, the one actual controller assertion
migration, real unchanged before/after characterization, meaningful old-markup
RED fallbacks, full native regressions and fresh final-source security. Trimmed
synthetic spaced fixture strings to avoid confusing DOM-string preservation with
incidental trailing whitespace, and aligned the scoped CSS with the selected
prototype (centered action, no inherited metadata underline, normal-weight
metadata). Actual checkpoint/installed-source/baseline-binding keys and the
read-only local-link script were checked. No implementation or runtime gate was
performed by this self-review.
