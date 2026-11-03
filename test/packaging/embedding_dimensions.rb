require "minitest/autorun"
require "yaml"

class EmbeddingDimensionsPackagingTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_checked_in_compose_passes_embedding_dimensions_to_migrations
    assert_shared_embedding_dimensions(File.read(File.join(ROOT, "docker-compose.yml")))
  end

  def test_shell_installer_passes_embedding_dimensions_to_migrations
    script = File.read(File.join(ROOT, "install.sh"))
    template = script.scan(/cat >{1,2} docker-compose\.yml <<EOF\n(.*?)^EOF$/m).flatten.join

    assert_shared_embedding_dimensions(template.gsub('\${', "${"))
  end

  def test_powershell_installer_passes_embedding_dimensions_to_migrations
    script = File.read(File.join(ROOT, "install.ps1"))
    template = script.match(/\$composeContent = @"\n(.*?)^"@$/m)[1]

    assert_shared_embedding_dimensions(template.gsub("`${", "${"))
  end

  private
    def assert_shared_embedding_dimensions(template)
      services = YAML.safe_load(template).fetch("services")

      %w[ db-migrate web solidq ].each do |name|
        assert_includes services.fetch(name).fetch("environment"),
          "EMBEDDING_DIMENSIONS=${EMBEDDING_DIMENSIONS}",
          "#{name} must receive the configured embedding width instead of defaulting to 768"
      end
    end
end
