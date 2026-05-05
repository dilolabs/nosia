module OpenAlex
  class Engine < ::Rails::Engine
    isolate_namespace OpenAlex

    config.open_alex = ActiveSupport::OrderedOptions.new

    initializer "open_alex.configuration" do |app|
      app.config.open_alex.api_key = ENV['OPENALEX_API_KEY']
      app.config.open_alex.base_url = 'https://api.openalex.org'
    end
  end
end