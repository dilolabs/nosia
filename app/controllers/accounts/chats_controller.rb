class Accounts::ChatsController < ApplicationController
  include AccountScoped

  PAGE_SIZE = 25

  def index
    @account = member_account(request.path_parameters.fetch(:account_id))
    value = params[:page]
    @page = value.is_a?(String) || value.is_a?(Numeric) ? [ value.to_i, 1 ].max : 1
    rows = @account.conversations_for(Current.user).offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE + 1).to_a
    @has_more = rows.length > PAGE_SIZE
    @conversations = rows.first(PAGE_SIZE)
    @titles = Chat.first_questions_for(@conversations)
  end
end
