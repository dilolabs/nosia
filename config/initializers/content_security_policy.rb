# Be sure to restart your server when you modify this file.

# Content security policy. Scripts are strict: 'self' plus a per-session
# nonce, no unsafe-inline — every inline <script> in the app is either ported
# to a Stimulus controller or carries an explicit nonce (the anti-FOUC theme
# bootstrap). Styles keep unsafe-inline for now: several views set runtime
# style attributes (progress widths) and Lexxy injects its own styles;
# tightening style-src needs those migrated to classes/custom properties.
#
# Note img-src allows remote https images because assistant markdown and
# crawled pages may legitimately embed them.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src :self
    policy.img_src :self, :data, :https
    policy.object_src :none
    policy.script_src :self
    policy.style_src :self, "'unsafe-inline'"
    policy.frame_ancestors :self
    policy.base_uri :self
  end

  # Session-scoped nonce so importmap/Turbo module scripts and the one
  # nonced inline script pass script-src. Store it explicitly because a fresh
  # browser's lazily initialized session has no ID on its first request.
  config.content_security_policy_nonce_generator = ->(request) { request.session[:csp_nonce] ||= SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
