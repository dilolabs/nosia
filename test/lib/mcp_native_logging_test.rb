require "test_helper"
require_relative "../support/chat_account_fixtures"
require_relative "../support/native_mcp_wire"

class McpNativeLoggingTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  test "only the fiber operating a native MCP client gets a quiet logger" do
    original = RubyLLM.config.logger
    output = StringIO.new
    inference_logger = Logger.new(output, level: Logger::DEBUG)
    RubyLLM.config.logger = inference_logger
    wire = NativeMcpWire.new
    wire.stream = wire.ping = true
    scope = McpOutbound::Scope.new(https_only: true)
    context = RubyLLM.context do |config|
      config.faraday_adapter = McpOutbound::Adapter
      config.logger = Logger.new(File::NULL)
    end
    native = context.mcp(name: "fixture", url: NativeMcpWire::URL, input_requests: false,
      headers: { "Authorization" => "Bearer #{NativeMcpWire::PRIVATE_MARKER}" })

    assert_same inference_logger, RubyLLM.logger
    RubyLLM.logger.debug("inference-before")
    wire.install(self) do
      McpOutbound.with(scope) do
        assert_equal [ "lookup" ], native.tools.map(&:server_name)
      ensure
        native.close
      end
    end
    assert wire.requests.any? { |request| request[:rpc]["id"] == "fixture-peer-ping" }
    refute_includes output.string, NativeMcpWire::PRIVATE_MARKER

    assert_raises(RuntimeError) do
      McpOutbound.with(McpOutbound::Scope.new(https_only: true)) do
        refute_same inference_logger, RubyLLM.logger
        RubyLLM.logger.debug("quiet-in-explicit-scope")
        Fiber.new do
          assert_same inference_logger, RubyLLM.logger
          RubyLLM.logger.debug("inference-other-fiber")
        end.resume
        assert_same inference_logger, Thread.new { RubyLLM.logger }.value
        raise "operation failed"
      end
    end

    assert_same inference_logger, RubyLLM.logger
    RubyLLM.logger.debug("inference-after")
    assert_includes output.string, "inference-before"
    assert_includes output.string, "inference-other-fiber"
    assert_includes output.string, "inference-after"
    refute_includes output.string, "quiet-in-explicit-scope"
  ensure
    RubyLLM.config.logger = original
  end
end
