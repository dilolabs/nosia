source "https://rubygems.org"

# Nosia dependency
gem "dotenv", groups: [ :development, :test ]

# Use main development branch of Rails
gem "rails", "~> 8.0.0"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails", "~> 3.3"
gem "tailwindcss-ruby", "~> 3.4"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# Use Redis adapter to run Action Cable in production
gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Nosia dependencies
  gem "bundler-audit"
  gem "dockerfile-rails"
  gem "mailbin"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end

# Nosia dependencies
gem "actioncable-enhanced-postgresql-adapter"
gem "acts_as_tenant"
gem "baran"
gem "commonmarker"
gem "faraday"
gem "feedjira"
gem "inline_svg"
gem "langchainrb", github: "patterns-ai-core/langchainrb", tag: "0.16.1"
gem "langchainrb_rails", github: "patterns-ai-core/langchainrb_rails", tag: "0.1.12"
gem "mission_control-jobs", github: "rails/mission_control-jobs", branch: "main"
gem "neighbor"
gem "pdf-reader"
gem "pgvector", "~> 0.2"
gem "passwordless"
gem "pundit"
gem "reverse_markdown"
gem "rss"
gem "ruby-openai", github: "nosia-ai/ruby-openai"
gem "sequel", "~> 5.94.0"
gem "solid_queue"
gem "thruster"
gem "tiktoken_ruby"
