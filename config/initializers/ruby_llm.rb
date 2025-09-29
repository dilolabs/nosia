module RubyLLM
  class Models
    class << self
      def models_file
        Rails.root.join('lib', 'ruby_llm', 'models.json')
      end
    end
  end
end

RubyLLM.configure do |config|
  config.default_model = ENV['LLM_MODEL']
  config.default_embedding_model = ENV['EMBEDDING_MODEL']
  config.openai_api_base = ENV['OPENAI_API_BASE']
  config.openai_api_key = ENV['OPENAI_API_KEY'] || Rails.application.credentials.dig(:openai_api_key)
  config.openai_use_system_role = true # Use 'system' role instead of 'developer'

  # Use the new association-based acts_as API (recommended)
  config.use_new_acts_as = true
end
