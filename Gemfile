source "https://rubygems.org"

# Nosia dependency
gem "dotenv", groups: [ :development, :test ] # A Ruby gem to load environment variables from `.env` [https://github.com/bkeepers/dotenv]

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
gem "tailwindcss-rails"
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
  gem "bundler-audit" # Patch-level verification for Bundler [https://github.com/rubysec/bundler-audit]
  gem "dockerfile-rails" # Rails generator to produce Dockerfiles and related files [https://github.com/fly-apps/dockerfile-rails]
  gem "mailbin" # Record and view Rails ActionMailer emails sent in development [https://github.com/excid3/mailbin]
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end

# Nosia dependencies
gem "actioncable-enhanced-postgresql-adapter" # An enhanced ActionCable adapter for PostgreSQL [https://github.com/reclaim-the-stack/actioncable-enhanced-postgresql-adapter]
gem "acts_as_tenant" # Row-level multitenancy [https://github.com/ErwinM/acts_as_tenant]
gem "baran" # Text Splitter for Large Language Model datasets [https://github.com/moeki0/baran]
gem "blingfire" # High speed text tokenization [https://github.com/ankane/blingfire-ruby]
gem "commonmarker" # CommonMark and GitHub Flavored Markdown compatible parser and renderer [https://github.com/gjtorikian/commonmarker]
gem "faraday" # HTTP client library abstraction layer [https://github.com/lostisland/faraday]
gem "inline_svg" # Embed SVG documents in views and style them with CSS [https://github.com/jamesmartin/inline_svg]
gem "mission_control-jobs" # Dashboard and Active Job extensions to operate and troubleshoot background jobs [https://github.com/rails/mission_control-jobs]
gem "neighbor" # Nearest neighbor search [https://github.com/ankane/neighbor]
gem "pdf-reader" # PDF parser conforming as much as possible to the PDF specification from Adobe [https://github.com/yob/pdf-reader]
gem "pgvector" # pgvector support for Ruby [https://github.com/pgvector/pgvector-ruby]
gem "pundit" # Minimal authorization through OO design and pure Ruby classes [https://github.com/varvet/pundit]
gem "ruby_llm" # Build chatbots, AI agents, RAG applications [https://github.com/crmne/ruby_llm]
gem "ruby_llm-mcp" # Model Context Protocol support for RubyLLM [https://github.com/crmne/ruby_llm-mcp]
gem "solid_queue" # Database-backed Active Job backend [https://github.com/rails/solid_queue]
gem "thruster" # HTTP/2 proxy for simple production-ready deployments [https://github.com/basecamp/thruster]
