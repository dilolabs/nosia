# Offline subprocess exercising RubyLLM's native JSON-RPC stdio transport.
require "json"

mode, trace = ARGV
STDOUT.sync = true

STDIN.each_line do |line|
  request = JSON.parse(line)
  method = request.fetch("method")
  reinitializing = method == "initialize" && File.readlines(trace, chomp: true).include?("initialize")
  File.open(trace, "a") { |file| file.puts(method) }
  next unless request.key?("id")

  if method == "tools/call" && mode == "disconnect"
    exit
  elsif method == "tools/call" && mode == "timeout"
    STDIN.read # Wait for the native client to close its pipe.
    break
  end

  result = case method
  when "server/discover"
    if mode == "reinitialize_error"
      { error: { code: -32_601, message: "fixture-private-error" } }
    elsif mode == "discovery_error"
      { error: { code: -32_020, message: "fixture-private-error" } }
    else
      { result: { supportedVersions: [ "2026-07-28" ], capabilities: { tools: {} } } }
    end
  when "initialize"
    if reinitializing
      { error: { code: -32_603, message: "fixture-private-error" } }
    else
      { result: { protocolVersion: "2025-11-25", capabilities: { tools: {} } } }
    end
  when "tools/list"
    { result: { tools: [ { name: "lookup", inputSchema: { type: "object" } } ] } }
  when "tools/call"
    { error: { code: -32_603, message: "fixture-private-error" } }
  else
    abort "unexpected request"
  end
  puts JSON.generate({ jsonrpc: "2.0", id: request.fetch("id") }.merge(result))
  exit if method == "tools/list" && mode == "reinitialize_error"
end
