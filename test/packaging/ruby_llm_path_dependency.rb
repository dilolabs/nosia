require "minitest/autorun"

class RubyLlmPathDependencyPackagingTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_vendor_directory_is_preserved_before_the_first_bundle_install
    instructions = File.readlines(File.join(ROOT, "Dockerfile")).map(&:strip)
    install_index = instructions.index { |line| line.match?(/\ARUN\s+bundle\s+install\b/) }

    refute_nil install_index, "Dockerfile must install the bundle"
    assert_includes instructions.take(install_index), "COPY vendor ./vendor",
      "Preserve vendor's directory name before Bundler resolves path gems"
    assert_includes instructions.take(install_index), "COPY Gemfile Gemfile.lock ./"
  end

  def test_the_gemfile_path_dependency_exists_in_the_build_context
    gemfile = File.read(File.join(ROOT, "Gemfile"))
    path = gemfile[/^gem "ruby_llm-mcp", path: "([^"]+)"/, 1]

    refute_nil path, "MCP must use an explicit vendored path"
    assert_equal "vendor/gems/ruby_llm-mcp", path
    assert File.file?(File.join(ROOT, path, "ruby_llm-mcp.gemspec")),
      "The vendored gemspec must exist at the exact Gemfile path"
  end
end
