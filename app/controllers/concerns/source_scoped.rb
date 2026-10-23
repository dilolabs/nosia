module SourceScoped
  extend ActiveSupport::Concern
  include AccountScoped
  include SourcesHelper

  included do
    before_action :set_source_account
    helper_method :source_account
  end

  private
    def set_source_account
      if request.path_parameters.key?(:account_id)
        @source_account = member_account(request.path_parameters.fetch(:account_id))
        @scoped_source_account = @account = @source_account
      else
        @source_account = Current.account
      end
    end

    def source_account
      @source_account
    end

    def verify_scoped_source_account
      if @scoped_source_account && params[controller_name.singularize].is_a?(ActionController::Parameters)
        submitted = params[controller_name.singularize][:account_id]
        unless submitted.nil?
          valid_scalar = submitted.is_a?(String) || submitted.is_a?(Numeric)
          raise ActiveRecord::RecordNotFound unless valid_scalar && submitted.to_s == source_account.id.to_s
        end
      end
    end

    def require_scoped_source_html
      if @scoped_source_account && !request.negotiate_mime([ Mime[:html] ])
        head :not_acceptable
      end
    end

    def source_filing_account(root)
      if @scoped_source_account
        source_account
      else
        id = params.dig(root, :account_id)
        raise ActiveRecord::RecordNotFound unless id.nil? || id.is_a?(String) || id.is_a?(Numeric)
        filing_account(root)
      end
    end
end
