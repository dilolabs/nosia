require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

class NativeEntrypointTest < Minitest::Test
  TOKEN = "00000000-0000-4000-8000-000000000001"

  def test_successful_operations_write_a_completion_marker
    with_entrypoint do |directory, script, environment|
      _, errors, status = Open3.capture3(environment, "sh", script, RbConfig.ruby, "-e", "exit 0")
      assert status.success?, errors
      assert_equal "complete\n", File.read(File.join(directory, "control", "#{TOKEN}.complete"))
    end
  end

  def test_long_running_commands_replace_the_entrypoint_for_direct_signal_delivery
    with_entrypoint do |_directory, script, environment|
      Open3.popen3(environment.merge("NOSIA_OPERATION_TOKEN" => nil), "sh", script,
        RbConfig.ruby, "-e", "puts Process.pid") do |input, output, errors, waiter|
        input.close
        assert_equal waiter.pid, Integer(output.read)
        assert waiter.value.success?, errors.read
      end
    end
  end

  def test_failed_retries_cannot_reuse_a_stale_completion_marker
    with_entrypoint do |directory, script, environment|
      marker = File.join(directory, "control", "#{TOKEN}.complete")
      File.write(marker, "complete\n")
      _, _, status = Open3.capture3(environment, "sh", script, RbConfig.ruby, "-e", "exit 7")
      assert_equal 7, status.exitstatus
      refute File.exist?(marker)
    end
  end

  def test_invalid_operation_tokens_are_rejected_before_the_command_runs
    with_entrypoint do |directory, script, environment|
      sentinel = File.join(directory, "command-ran")
      [ "abc", "--", "-" * 36, "../escape", "#{TOKEN}\n", "#{TOKEN}0" ].each do |token|
        _, _, status = Open3.capture3(environment.merge("NOSIA_OPERATION_TOKEN" => token), "sh", script,
          RbConfig.ruby, "-e", "File.write(ARGV.fetch(0), 'ran')", sentinel)
        refute status.success?, "Accepted invalid operation token #{token.inspect}"
        refute File.exist?(sentinel), "Command ran before validating #{token.inspect}"
      end
    end
  end

  def test_missing_control_mount_is_rejected_before_the_command_runs
    with_entrypoint do |directory, script, environment|
      FileUtils.rmdir(File.join(directory, "control"))
      sentinel = File.join(directory, "command-ran")
      _, _, status = Open3.capture3(environment, "sh", script,
        RbConfig.ruby, "-e", "File.write(ARGV.fetch(0), 'ran')", sentinel)
      refute status.success?
      refute File.exist?(sentinel)
    end
  end

  def test_backup_paths_cannot_escape_the_backup_directory
    with_entrypoint do |directory, script, environment|
      destination = File.join(directory, "backups", "..", "escaped.tar.partial")
      _, _, status = Open3.capture3(environment, "sh", script, "nosia-native-backup", destination)
      refute status.success?
      refute File.exist?(destination)
    end
  end

  def test_backup_archives_the_document_volume_and_confirms_success
    with_entrypoint do |directory, script, environment|
      destination = File.join(directory, "backups", "snapshot.tar.partial")
      File.write(File.join(directory, "rails/storage/document"), "document content")
      _, errors, status = Open3.capture3(environment, "sh", script, "nosia-native-backup", destination)
      assert status.success?, errors
      contents, errors, status = Open3.capture3("tar", "-xOf", destination, "./document")
      assert status.success?, errors
      assert_equal "document content", contents
      assert File.exist?(File.join(directory, "control", "#{TOKEN}.complete"))
    end
  end

  private
    def with_entrypoint
      Dir.mktmpdir("nosia-entrypoint") do |directory|
        %w[rails/storage rails/tmp/pids backups control commands].each do |path|
          FileUtils.mkdir_p(File.join(directory, path))
        end
        # Keep real shell, command execution and tar behavior. Only privileged
        # ownership/user switching is substituted for this unprivileged sandbox.
        File.write(File.join(directory, "commands/chown"), "#!/bin/sh\nexit 0\n")
        File.write(File.join(directory, "commands/runuser"), "#!/bin/sh\nshift 3\n\"$@\"\nstatus=$?\nexit \"$status\"\n")
        File.write(File.join(directory, "commands/setpriv"), "#!/bin/sh\nshift 4\nexec \"$@\"\n")
        FileUtils.chmod(0755, Dir.glob(File.join(directory, "commands/*")))
        root = File.expand_path("../../..", __dir__)
        source = File.read(File.join(root, "bin/nosia-entrypoint"))
          .gsub("/rails", File.join(directory, "rails"))
          .gsub("/backups", File.join(directory, "backups"))
          .gsub("/nosia-control", File.join(directory, "control"))
        script = File.join(directory, "entrypoint")
        File.write(script, source)
        environment = { "NOSIA_NATIVE_LOCAL" => "1", "NOSIA_OPERATION_TOKEN" => TOKEN,
          "PATH" => "#{directory}/commands:#{ENV.fetch('PATH')}" }
        yield directory, script, environment
      end
    end
end
