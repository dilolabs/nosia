require "test_helper"

class Chunk::EnrichableTest < ActiveSupport::TestCase
  test "enrichment sends max_tokens as flat provider options and replaces instructions" do
    calls = []
    fake = Object.new
    fake.define_singleton_method(:with_provider_options) { |**options| calls << [ :options, options ]; self }
    fake.define_singleton_method(:with_instructions) { |text, **options| calls << [ :instructions, text, options ]; self }
    fake.define_singleton_method(:ask) { |prompt| Struct.new(:content).new("One, Two\nWhy?") }
    original = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**options| calls << [ :chat, options ]; fake }
    chunk = Chunk.new(content: "Original text", metadata: {})
    chunk.define_singleton_method(:save!) { true }

    chunk.enrich!

    assert_equal [ 20, 100, 50, 150 ], calls.select { |call| call.first == :options }.map { |call| call.last.fetch(:max_tokens) }
    assert_equal 4, calls.count { |call| call == [ :chat, { model: ENV["LLM_MODEL"], provider: :openai, assume_model_exists: true } ] }
    assert_equal [ {}, {}, {}, {} ], calls.select { |call| call.first == :instructions }.map(&:last)
    assert_equal "One, Two\nWhy?", chunk.metadata[:title]
    assert_equal [ "One", "Two", "Why?" ], chunk.metadata[:keywords]
    assert_equal [ "Why?" ], chunk.metadata[:potential_questions]
  ensure
    RubyLLM.define_singleton_method(:chat, original) if original
  end
end
