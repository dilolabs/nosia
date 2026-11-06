# frozen_string_literal: true

# Reconstructed from the published 1.0.1 gem's metadata; see PATCHES.md.
Gem::Specification.new do |spec|
  spec.name = "ruby_llm-mcp"
  spec.version = "1.0.1"
  spec.authors = [ "Patrick Vice" ]
  spec.email = [ "patrickgvice@gmail.com" ]
  spec.summary = "A RubyLLM MCP Client"
  spec.description = <<~DESCRIPTION
    A Ruby client for the Model Context Protocol (MCP) that seamlessly integrates with RubyLLM.
    Supports both native full-featured implementation and the official mcp-sdk gem.
    Connect to MCP servers via SSE, stdio, or HTTP transports, automatically convert MCP tools into
    RubyLLM-compatible tools, and enable AI models to interact with external data sources and
    services. Makes using MCP with RubyLLM as easy as possible.
  DESCRIPTION
  spec.homepage = "https://www.rubyllm-mcp.com"
  spec.licenses = [ "MIT" ]
  spec.date = "1980-01-02"
  spec.required_ruby_version = ">= 3.1.3"
  spec.required_rubygems_version = ">= 0"
  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "bug_tracker_uri" => "https://github.com/patvice/ruby_llm-mcp/issues",
    "changelog_uri" => "https://github.com/patvice/ruby_llm-mcp/commits/main",
    "documentation_uri" => "https://www.rubyllm-mcp.com/guides/",
    "homepage_uri" => "https://www.rubyllm-mcp.com",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/patvice/ruby_llm-mcp"
  }
  spec.require_paths = [ "lib" ]
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "LICENSE", "README.md", "PATCHES.md"].select { |path| File.file?(path) }.sort
  end

  spec.add_dependency "httpx", "~> 1.4"
  spec.add_dependency "json-schema", ">= 5.0", "< 7"
  spec.add_dependency "json_schemer", "~> 2.4"
  spec.add_dependency "ruby_llm", "= 2.1.1"
  spec.add_dependency "zeitwerk", "~> 2"
end
