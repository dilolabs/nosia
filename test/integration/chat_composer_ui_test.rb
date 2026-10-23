require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_account_fixtures"

class ChatComposerUiTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable::TestHelper

  setup { sign_in_picker_user }

  test "both new-chat entry points share selected-account composer controls" do
    [ user_root_url, new_chat_url ].each do |url|
      get url, params: { account_id: @second.id, model: "picker-test-model" }

      assert_response :success
      assert_select "#chat-form .n-chat-composer .n-composer-surface", count: 1
      assert_select "#chat-form lexxy-editor[name='chat[prompt]'][data-composer-target=editor][data-composer-sources-target=editor]"
      assert_select "#chat-form input[type=hidden][name='chat[attached_website_ids][]'][multiple][data-composer-sources-target=websiteIds]"
      assert_select "#chat-form input[type=hidden][name='chat[attached_document_ids][]'][multiple][data-composer-sources-target=documentIds]"
      assert_select "#chat-form input[type=hidden][name='chat[model]'][value='picker-test-model']"
      assert_select "#chat-form #mcp-server-hidden-fields[data-mcp-fields-sync-target=hiddenFields]"
      assert_select ".n-composer-actions select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
      assert_select "[data-composer-tools]", count: 1 do |tools|
        assert_select "input[type=checkbox][name='mcp_server_ids[]'][value='#{mcp_servers(:picker_second_tool).id}']", count: 1
        assert_select "input[type=checkbox]", count: 1
        refute_match(/\d*ms\b/, tools.first.text)
      end
      assert_select "#chat-account-help", text: "Searches and attachments use this account."
      assert_select ".n-composer-actions button[aria-label=Send][data-chat-account-target=send]"
      assert_select ".n-composer-validation", count: 0
      assert_select "form form", count: 0
    end
  end

  test "generating saved chat uses a separate Stop form without creating a message" do
    chat = chats(:picker_second_chat)
    chat.start_generation!

    get chat_url(chat)

    assert_response :success
    assert_select "turbo-frame[id='#{dom_id(chat)}_message_form']", count: 1 do
      assert_select ".n-chat-composer .n-composer-surface", count: 1
      assert_select "form[action='#{chat_messages_path(chat)}']" do
        assert_select "lexxy-editor[name='message[content]'][disabled]"
        assert_select "input[type=hidden][name='message[attached_website_ids][]'][multiple][data-composer-sources-target=websiteIds]"
        assert_select "input[type=hidden][name='message[attached_document_ids][]'][multiple][data-composer-sources-target=documentIds]"
        assert_select "[data-chat-account-readonly]", text: /Research team/
        assert_select "select[name='chat[account_id]']", count: 0
        assert_select "button[aria-label=Send]", count: 0
        assert_select "button[type=submit][aria-label='Stop generating'][form='#{dom_id(chat, :composer_stop)}']", count: 1
      end
      assert_select "form[id='#{dom_id(chat, :composer_stop)}'][method=post][action='#{stop_chat_path(chat)}'][data-turbo-frame='_top']", count: 1
    end
    assert_select "form form", count: 0
    counts = [ Chat.count, Message.count ]

    assert_no_enqueued_jobs only: ChatResponseJob do
      post stop_chat_url(chat)
    end

    assert_redirected_to chat_url(chat)
    refute_predicate chat.reload, :generating?
    assert_predicate chat, :generation_stopped?
    assert_equal counts, [ Chat.count, Message.count ]
  end

  test "saved composer renders without request-scoped Current" do
    chat = chats(:picker_second_chat)
    Current.reset

    html = ApplicationController.render(partial: "messages/form", locals: { chat: chat })
    fragment = Nokogiri::HTML.fragment(html)

    assert_select fragment, ".n-chat-composer .n-composer-surface", count: 1
    assert_select fragment, "[data-chat-account-readonly]", text: /Research team/
    assert_select fragment, "button[aria-label=Send][data-chat-account-target=send]", count: 1
    assert_select fragment, "select[name='chat[account_id]']", count: 0
  end

  test "background unlock broadcast uses the shared saved presentation" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    Current.reset

    streams = capture_turbo_stream_broadcasts([ chat, "messages", :en ]) { chat.finish_generation! }
    replacement = streams.find { |stream| stream["target"] == "#{dom_id(chat)}_message_form" }

    assert replacement
    fragment = Nokogiri::HTML.fragment(replacement.inner_html)
    assert_select fragment, ".n-chat-composer", count: 1
    assert_select fragment, "button[aria-label=Send]:not([disabled])"
    assert_select fragment, "lexxy-editor:not([disabled])"
    assert_select fragment, "[data-chat-account-target=editingTools][aria-disabled=false]:not([inert])"
    assert_select fragment, "[data-chat-account-readonly]", text: /Research team/
  end

  test "composer validation errors are announced and escaped" do
    chat = @user.chats.new(account: @second)
    chat.errors.add(:base, "Invalid <script>message</script>")

    html = Current.set(session: Session.new(user: @user)) do
      ApplicationController.render(partial: "chats/form", locals: { chat: chat })
    end
    fragment = Nokogiri::HTML.fragment(html)

    assert_select fragment, ".n-composer-validation[role=alert]", text: /Invalid <script>message<\/script>/
    assert_select fragment, "script", count: 0
  end

  test "accounts without tools or skills omit optional controls and no-account users have no composer" do
    @first.mcp_servers.destroy_all
    @first.agent_skills.destroy_all

    get new_chat_url

    assert_response :success
    assert_select ".n-chat-composer", count: 1
    assert_select "[data-composer-tools]", count: 0
    assert_select ".n-composer-hints", count: 1 do |hints|
      refute_match(/skills/, hints.first.text)
    end

    delete logout_url
    sign_in_picker_user(users(:picker_no_account))
    get new_chat_url

    assert_response :success
    assert_select "[data-chat-no-account]", count: 1
    assert_select ".n-chat-composer", count: 0
    assert_select "lexxy-editor", count: 0
  end
end
