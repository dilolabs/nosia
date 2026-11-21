RubyLLM.configure do |config|
  config.default_model = ENV["LLM_MODEL"]
  config.default_embedding_model = ENV["EMBEDDING_MODEL"]
  config.openai_api_base = ENV["AI_BASE_URL"]
  config.openai_api_key = ENV["AI_API_KEY"]
  config.openai_protocol = :chat_completions
  config.openai_use_system_role = true # Use 'system' role instead of 'developer'
end

if Gem.loaded_specs.fetch("ruby_llm").version == Gem::Version.new("2.2.3")
  require Rails.root.join("lib/nosia/private_embedding_usage")
  # RubyLLM 2.2 writes standalone usage before returning the vector, with no
  # per-context ledger option. Notes record validated usage at publication.
  RubyLLM::Accounting::Usage.singleton_class.prepend(Nosia::PrivateEmbeddingUsage)

  # Remove once the pinned gem routes its native HTTP diagnostics through
  # the context logger and test/lib/mcp_native_logging_test.rb passes without this.
  quiet_mcp_logger = Logger.new(File::NULL)
  RubyLLM.singleton_class.prepend(Module.new do
    define_method(:logger) do
      if defined?(McpOutbound) && McpOutbound.active?
        quiet_mcp_logger
      else
        super()
      end
    end
  end)
end
