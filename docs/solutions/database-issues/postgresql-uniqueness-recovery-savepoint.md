---
title: "Recover concurrent URL inserts without aborting the chat transaction"
date: "2026-10-15"
problem_type: database_issue
component: "Website registration inside Chat transactions"
symptoms:
  - "Concurrent URL registration raises PG::UniqueViolation."
  - "The recovery lookup raises PG::InFailedSqlTransaction during chat creation."
tags: [postgresql, activerecord, record-not-unique, savepoints, concurrency]
---

## Problem

Two requests can pass URL uniqueness validation before either inserts. The losing
INSERT raises `ActiveRecord::RecordNotUnique`. Previously, rescuing that error and
looking up the winner worked because registration had no enclosing transaction.
Inside the new `Chat.transaction`, PostgreSQL leaves the transaction aborted, so
the recovery query fails and the chat cannot be created.

## Solution

In the new-record branch of `Website.find_or_create_by_url!`, isolate the insert:

```ruby
begin
  transaction(requires_new: true) { website.save! }
  CrawlWebsiteUrlJob.perform_later(website.id)
rescue ActiveRecord::RecordNotUnique
  website = account.websites.find_by!(url: url)
end
```

Rescue **outside** the savepoint block so Rails rolls it back before querying the
winner. The caller's transaction remains usable, and only the successful inserter
enqueues a crawl. Keep `CrawlWebsiteUrlJob.enqueue_after_transaction_commit = true`:
releasing a savepoint is not the outer commit, and an outer rollback must cancel
publication. Do not retry the whole chat or broadly rescue database errors.

## Regression coverage

- `test/controllers/chat_account_url_race_test.rb` coordinates distinct PostgreSQL
  connections after the losing uniqueness check. It requires a real
  `PG::UniqueViolation`, not a simulated Ruby exception, and verifies successful
  selected-account creation, winner references, and one generation/crawl job.
- It also covers outer rollback and standalone registration. Queue barriers avoid
  sleeps; threads, connections, notifications, and committed fixtures are cleaned up.
- `test/jobs/crawl_website_url_job_transaction_test.rb` verifies publication after
  the outer commit, worker visibility, and cancellation on rollback.

The race regression passes with three tests and 54 assertions. See
[chat account selection](../../chat-account-selection.md#engineering-notes) for
the surrounding account boundary and qualified full-suite verification results.
