# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :embedding, :config, :mcp_server
]

require Rails.root.join("lib/mcp_oauth_callback_query")
Rails.application.config.middleware.insert_before Rails::Rack::Logger, McpOauthCallbackQuery

# Use exact names rather than matching unrelated parameter names containing
# "code" or "state". The callback's entire query is kept outside Rails params.
oauth_fields = %w[
  code state error_description code_verifier code_challenge access_token refresh_token id_token
  client_secret client_assertion assertion private_key dpop dpop_key dpop_nonce authorization authorization_code
]
Rails.application.config.filter_parameters += oauth_fields.map { |key| /\A#{key}\z/i }
Rails.application.config.filter_parameters << /\Anosia\.mcp_oauth_callback_query\z/

Rails.application.config.filter_parameters << /\Anote\.(?:title|body_html)\z/i
