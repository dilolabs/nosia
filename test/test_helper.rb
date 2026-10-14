ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Stubs UrlGuard DNS resolution so SSRF-guard tests never touch real DNS.
    # Pair with unstub_url_resolver in teardown.
    def stub_url_resolver(ips)
      @original_url_resolve ||= UrlGuard.method(:resolve).unbind
      addresses = Array(ips).map { |ip| IPAddr.new(ip) }
      UrlGuard.define_singleton_method(:resolve) { |_host| addresses }
      @stubbed_url_resolver = true
    end

    def unstub_url_resolver
      return unless @stubbed_url_resolver

      UrlGuard.define_singleton_method(:resolve, @original_url_resolve)
      @stubbed_url_resolver = false
    end

    # Stubs a Chat's ruby_llm pre-amble + streaming entry so complete_with_nosia
    # runs the real coalescing loop with canned chunks (no LLM, no embeddings).
    StreamChunk = Struct.new(:content)

    def stub_chat_for_streaming(chat, chunks:)
      chat.define_singleton_method(:mcp_tools) { [] }
      chat.define_singleton_method(:with_model) { |*| }
      chat.define_singleton_method(:with_provider_options) { |*| }
      chat.define_singleton_method(:with_temperature) { |*| }
      chat.define_singleton_method(:with_instructions) { |*| }
      chat.define_singleton_method(:similarity_search) { |*| [] }
      chat.define_singleton_method(:system_prompt) { "x" }
      chat.define_singleton_method(:broadcast_thinking_phase) { |*| }
      chat.define_singleton_method(:answer_relevance) { |*| true }
      chat.define_singleton_method(:record_completion_usage!) { |*| }
      chat.define_singleton_method(:complete) do |&blk|
        chunks.each { |c| blk.call(c) }
        messages.last
      end
    end

    # Add more helper methods to be used by all tests here...
  end
end
