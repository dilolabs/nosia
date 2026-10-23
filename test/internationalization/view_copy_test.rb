require "test_helper"
require "tempfile"
require_relative "../support/localized_view_assertions"

class ViewCopyTest < ActiveSupport::TestCase
  include LocalizedViewAssertions

  test "shell and authentication sources have no uncatalogued UI literals" do
    assert_localized_view_sources Dir.glob(Rails.root.join("app/views/{application,layouts,static,sessions,users,first_runs}/**/*.erb"))
  end

  test "chat sources have no uncatalogued UI literals" do
    usage_partials = %w[app/views/chats/_token_totals.html.erb app/views/messages/_token_footer.html.erb].map { |path| Rails.root.join(path).to_s }
    paths = Dir.glob(Rails.root.join("app/views/{chats,messages,chat_mcp_sessions,dashboards,chunks}/**/*.erb"))

    assert_localized_view_sources paths - usage_partials
  end

  test "source workflows have no uncatalogued UI literals" do
    assert_localized_view_sources Dir.glob(Rails.root.join("app/views/sources/**/*.erb"))
  end

  test "account and administration screens have no uncatalogued UI literals" do
    assert_localized_view_sources Dir.glob(Rails.root.join("app/views/{accounts,settings,api_tokens,system_prompts,models}/**/*.erb"))
  end

  {
    "original sign in submit" => [ "Sign in", '<%= form.submit "Sign in", class: "n-btn-primary" %>' ],
    "original sign up submit" => [ "Sign up", '<%= form.submit "Sign up", class: "n-btn-primary" %>' ],
    "submit tag" => [ "Save", '<%= submit_tag "Save", name: "commit" %>' ],
    "form button" => [ "Save", '<%= form.button("Save", class: "n-btn") %>' ],
    "button tag" => [ "Cancel", '<%= button_tag "Cancel", type: "button" %>' ],
    "button to" => [ "Delete", '<%= button_to "Delete", chat_path(chat), method: :delete %>' ],
    "link to" => [ "Home", "<%= link_to('Home', root_path, class: 'n-nav-link') %>" ],
    "interpolated link label" => [ "Edit", '<%= link_to "Edit #{user.name}", user_path(user) %>' ],
    "form label" => [ "Email address", '<%= form.label :email, "Email address", class: "font-medium" %>' ],
    "label tag" => [ "Email address", '<%= label_tag(:email, "Email address") %>' ],
    "original email placeholder" => [ "Enter your email address", '<%= form.email_field :email, required: true, autocomplete: "username", placeholder: "Enter your email address", value: params[:email], class: "n-field" %>' ],
    "original password placeholder" => [ "Enter your password", '<%= form.password_field :password, autocomplete: "current-password", placeholder: "Enter your password", maxlength: 72 %>' ],
    "original signup confirmation placeholder" => [ "Enter your password confirmation", '<%= form.password_field :password_confirmation, placeholder: "Enter your password confirmation" %>' ],
    "field tag placeholder" => [ "Search...", '<%= text_field_tag :query, params[:query], :placeholder => "Search..." %>' ],
    "title option" => [ "User info", '<%= link_to user.name, user_path(user), title: "User info" %>' ],
    "alt option" => [ "Company logo", '<%= image_tag "logo.png", alt: "Company logo" %>' ],
    "aria label option" => [ "Search", '<%= form.text_field :query, "aria-label": "Search" %>' ],
    "Rails aria label" => [ "Delete chat", '<%= button_to chat, method: :delete, aria: { label: "Delete chat" } do %><%= chat.title %><% end %>' ],
    "string keyed Rails aria label" => [ "Open menu", '<%= button_tag type: "button", "aria" => { "label" => "Open menu" } do %><%= user.name %><% end %>' ],
    "confirmation option" => [ "Are you sure?", '<%= button_to chat, method: :delete, data: { turbo_confirm: "Are you sure?" } do %><%= chat.title %><% end %>' ],
    "page title" => [ "Sign in", '<% content_for :title, "Sign in" %>' ],
    "raw submit value" => [ "Sign in", '<input type="submit" value="Sign in">' ],
    "raw button value" => [ "Save", '<input type="button" value="Save">' ],
    "raw reset value" => [ "Reset", '<input type="reset" value="Reset">' ]
  }.each do |name, (copy, source)|
    test "audit rejects #{name}" do
      with_view_source(source) do |path|
        error = assert_raises(Minitest::Assertion, "Audit accepted #{source}") do
          assert_localized_view_sources [ path ]
        end

        assert_includes error.message, copy
      end
    end
  end

  test "audit allows translated labels and options in form blocks" do
    source = <<~ERB
      <%= form_with model: user, url: "/users", class: "flex border-neutral-300" do |form| %>
        <%= form.label :email, t("nosia.auth.email_placeholder"), class: "font-medium" %>
        <%= form.email_field :email, autocomplete: "username", placeholder: t("nosia.auth.email_placeholder"), value: params[:email], class: "n-field" %>
        <%= form.password_field :password_confirmation, placeholder: t("nosia.auth.confirmation_placeholder") %>
        <%= form.submit t("nosia.auth.sign_in"), class: "n-btn-primary" %>
        <%= form.button t("nosia.actions.save"), title: t("nosia.actions.save"), aria: { label: t("nosia.actions.save") } %>
      <% end %>
      <%= link_to t("nosia.nav.home"), "/", title: t("nosia.nav.home_page") %>
      <%= button_to t("nosia.actions.delete"), user_path(user), data: { turbo_confirm: t("nosia.actions.confirm_delete") } %>
      <% content_for :title, t("nosia.auth.sign_in") %>
      <input type="submit" value="<%= t("nosia.auth.sign_in") %>">
    ERB

    with_view_source(source) { |path| assert_localized_view_sources [ path ] }
  end

  test "audit allows authored values and technical helper arguments" do
    source = <<~ERB
      <%= link_to user.name, { controller: "users", action: "show", id: user.id }, class: "n-nav-link", title: user.bio, aria: { label: user.name } %>
      <%= link_to t("nosia.nav.home"), search_path(title: "query", label: "filter") %>
      <%= link_to "/users", title: user.bio do %><%= user.name %><% end %>
      <%= button_to "/chats", method: :delete do %><%= chat.title %><% end %>
      <%= button_to chat.title, "/chats", method: :delete, data: { turbo_confirm: confirmation } %>
      <%= form.button :draft, value: "draft", class: "n-btn" %>
      <%= form.label "email_address", class: "font-medium" %>
      <%= label_tag "email_address" %>
      <%= form.text_field :name, value: "Jane Doe", autocomplete: "given-name", class: "n-field" %>
      <%= image_tag "nosia-logo.png", alt: "", class: "h-8" %>
      <%= form.text_field :endpoint, placeholder: "https://your-mcp-server.com/mcp" %>
      <%= inline_svg "svg/files.svg", title: "PDF", class: "w-6 h-6" %>
      <% content_for :title, chat.title %>
      <input type="text" value="Authored content">
      <input type="hidden" value="PATCH">
      <%= chat.title %>
      <p>Nosia</p>
      <%# link_to "Commented example", root_path %>
      <% if content_for(:navbar) %><%= yield(:navbar) %><% end %>
    ERB

    with_view_source(source) { |path| assert_localized_view_sources [ path ] }
  end

  private
    def with_view_source(source)
      Tempfile.create([ "localized-view", ".html.erb" ]) do |file|
        file.write(source)
        file.flush
        yield file.path
      end
    end
end
