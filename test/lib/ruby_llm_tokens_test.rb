require "test_helper"

class RubyLlmTokensTest < ActiveSupport::TestCase
  test "standard input excludes cache reads and writes" do
    tokens = RubyLLM::Tokens.new(input: 80, output: 20, cache_read: 15, cache_write: 5)

    assert_respond_to tokens, :cache_read
    assert_respond_to tokens, :cache_write
    assert_equal 80, tokens.input
    assert_equal 100, tokens.input + tokens.cache_read + tokens.cache_write
    assert_equal 20, tokens.output
  end
end
