require "bundler/setup"
require "minitest/autorun"
require "ruby_llm"
require "mcp"

class RubyLlmMcpPackagingTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_native_mcp_is_bundled_without_the_vendored_bridge
    assert_equal Gem::Version.new("2.2.3"), Gem.loaded_specs.fetch("ruby_llm").version
    assert_instance_of Class, MCP::Tool
    client = RubyLLM.mcp(name: "packaging", url: "https://mcp.example.test")
    assert_kind_of RubyLLM::MCP, client
    assert_equal "packaging", client.name
    assert_respond_to client, :tools
    assert_respond_to client, :close
    refute_includes Bundler.load.specs.map(&:name), "ruby_llm-mcp"
    refute File.exist?(File.join(ROOT, "vendor/gems/ruby_llm-mcp"))
    assert_raises(LoadError) { require "ruby_llm/mcp/native" }
  end

  def test_docker_installs_the_bundle_and_still_copies_the_application
    dockerfile = File.readlines(File.join(ROOT, "Dockerfile")).map(&:strip)
    install = dockerfile.index { |line| line.match?(/\ARUN\s+bundle\s+install\b/) }
    refute_nil install
    assert_includes dockerfile.take(install), "COPY Gemfile Gemfile.lock ./"
    assert_includes dockerfile.drop(install), "COPY . ."
  end
end
