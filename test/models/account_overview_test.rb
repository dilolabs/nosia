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
