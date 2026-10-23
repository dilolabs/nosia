require "test_helper"
require_relative "../support/account_experience_fixtures"

class AccountOverviewTest < ActiveSupport::TestCase
  include AccountExperienceFixtures

  test "directory summaries count only sources and the viewer's root chats" do
    counts = Account.overview_counts_for([ @first, @second, @empty ], user: @user)

    assert_equal({ sources: 2, conversations: 1 }, counts.fetch(@first.id))
    assert_equal({ sources: 4, conversations: 28 }, counts.fetch(@second.id))
    assert_equal({ sources: 0, conversations: 0 }, counts.fetch(@empty.id))
    refute counts.key?(@foreign.id)
    assert_equal 1, Account.overview_counts_for([ @second ], user: @member).fetch(@second.id)[:conversations]
  end

  test "recent chats are ordered and restricted to this account and viewer" do
    rows = @second.conversations_for(@user).limit(5).to_a

    assert_equal 5, rows.size
    assert_equal experience(:chats, :overview_second_chat_27).id, rows.first.id
    assert rows.all? { |chat| chat.account_id == @second.id && chat.user_id == @user.id && chat.chat_id.nil? }
  end

  test "nonempty directory summaries use exactly five grouped queries regardless of account count" do
    [ [ @second ], [ @first, @second, @empty ] ].each do |accounts|
      statements = []
      subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA" }
      Account.uncached do
        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { Account.overview_counts_for(accounts, user: @user) }
      end

      selects = statements.grep(/\ASELECT\b/i)
      assert_equal 5, selects.size
      assert_equal %w[chats documents qnas texts websites], selects.map { |sql| sql[/\bFROM\s+["`]?([a-z_]+)/i, 1] }.sort
      selects.each { |sql| assert_match(/COUNT\(.*GROUP BY/im, sql) }
    end
  end

  test "chat activity ties use descending numeric IDs independently of message titles" do
    first = experience(:chats, :overview_second_chat_0)
    second = experience(:chats, :overview_second_chat_1)
    timestamp = Time.utc(2030, 1, 1)
    first.update_columns(updated_at: timestamp)
    second.update_columns(updated_at: timestamp)

    assert_equal [ first.id, second.id ].sort.reverse, @second.conversations_for(@user).limit(2).map(&:id)
    experience(:messages, :overview_second_question_0).update_columns(content: nil)
    assert_nil Chat.first_questions_for([ first ]).fetch(first.id)
    assert_empty Chat.first_questions_for([])
  end

  test "first user messages with equal timestamps use ascending numeric message IDs" do
    chat = experience(:chats, :overview_second_chat_0)
    first = experience(:messages, :overview_second_question_0)
    second = experience(:messages, :overview_second_question_1)
    second.update_columns(chat_id: chat.id, created_at: first.created_at)
    expected = [ first, second ].min_by(&:id).content

    assert_equal expected, Chat.first_questions_for([ chat ]).fetch(chat.id)
  end

  test "first questions are fetched in one query and preserve first-user-message semantics" do
    rows = @second.conversations_for(@user).limit(5).to_a
    statements = []
    subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA" }
    titles = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { Chat.first_questions_for(rows) }

    assert_equal "Research question 27", titles.fetch(rows.first.id)
    assert_equal 1, statements.grep(/SELECT/i).size
  end

  test "first questions use the earliest user message and remove its context" do
    chat = experience(:chats, :overview_second_chat_27)
    question = experience(:messages, :overview_second_question_27)
    question.update_columns(content: "<context>Private evidence</context><p>First question</p>")
    Message.insert_all!([
      { chat_id: chat.id, role: Message.roles.fetch("system"), content: "System instructions", created_at: question.created_at - 1.minute },
      { chat_id: chat.id, role: Message.roles.fetch("assistant"), content: "Earlier answer", created_at: question.created_at - 1.second },
      { chat_id: chat.id, role: Message.roles.fetch("user"), content: "Later question", created_at: question.created_at + 1.minute }
    ])

    assert_equal({ chat.id => "<p>First question</p>" }, Chat.first_questions_for([ chat ]))
  end

  test "first questions retain a blank first message and omit chats without user messages" do
    chat = experience(:chats, :overview_second_chat_27)
    child = experience(:chats, :overview_child_chat)
    question = experience(:messages, :overview_second_question_27)
    question.update_columns(content: nil)
    Message.insert_all!([
      { chat_id: chat.id, role: Message.roles.fetch("user"), content: "Later question", created_at: question.created_at + 1.minute }
    ])

    assert_equal({ chat.id => nil }, Chat.first_questions_for([ chat, child ]))
  end

  test "empty directory summaries do not query the database" do
    statements = []
    subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA" }
    counts = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { Account.overview_counts_for([], user: @user) }

    assert_empty counts
    assert_empty statements.grep(/SELECT/i)
  end

  test "empty first questions do not query the database" do
    statements = []
    subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA" }
    titles = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { Chat.first_questions_for([]) }

    assert_empty titles
    assert_empty statements.grep(/SELECT/i)
  end
end
