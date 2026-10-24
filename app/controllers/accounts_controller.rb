# frozen_string_literal: true

class AccountsController < ApplicationController
  include AccountScoped

  PAGE_SIZE = 24

  before_action :set_account, only: [ :show, :edit, :update ]
  before_action :require_account_owner, only: [ :edit, :update ]

  def index
    @page = positive_page
    rows = Current.user.accounts.order(:name, :id).offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE + 1).to_a
    @has_more = rows.length > PAGE_SIZE
    @accounts = rows.first(PAGE_SIZE)
    @counts = Account.overview_counts_for(@accounts, user: Current.user)
  end

  def show
    @source_counts = SourceRow.counts_for(@account)
    @conversations = @account.conversations_for(Current.user).limit(5).to_a
    @titles = Chat.first_questions_for(@conversations)
    @users_count = @account.account_users.count
    @api_tokens_count = Current.user.api_tokens.where(account: @account).count
    @shared_prompt = @account.system_prompt
    @token_totals = { input: @account.input_tokens_count, output: @account.output_tokens_count }
  end

  def new
    @account = Current.user.accounts.new
  end

  def edit
  end

  def create
    @account = Current.user.accounts.create_with_system_prompt!(account_params.merge(owner: Current.user))
    redirect_to account_path(@account)
  rescue ActiveRecord::RecordInvalid => error
    raise unless error.record.is_a?(Account)

    @account = error.record
    render :new, status: :unprocessable_entity
  end

  def update
    if @account.update(account_params)
      redirect_to account_path(@account), notice: t("nosia.accounts.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def positive_page
      value = params[:page]
      page = value.is_a?(String) || value.is_a?(Numeric) ? value.to_i : 1
      page.between?(1, (2**63 - 1) / PAGE_SIZE) ? page : 1
    end

    def set_account
      @account = member_account(request.path_parameters.fetch(:id))
    end

    def account_params
      params.require(:account).permit(:name, :uid)
    end
end
