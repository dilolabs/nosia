module AgentSkill::Security
  extend self

  FILE_ALLOWLIST = %w[.md .markdown .txt .yaml .yml .json].freeze
  MAX_FILE_SIZE = ENV.fetch("AGENT_SKILLS_MAX_FILE_SIZE", 1_048_576).to_i
  MAX_TOTAL_SIZE = 10 * MAX_FILE_SIZE

  PROMPT_INJECTION_PATTERNS = [
    /<\/im\s*start\s*of\s*prompt>/i,
    /<\/im\s*end\s*of\s*prompt>/i,
    /<\/im\s*instruction>/i,
    /<\/user>/i,
    /<\/assistant>/i,
    /<\/system>/i,
    /<\|im\s*start\s*of\s*prompt\s*>/i,
    /<\|im\s*end\s*of\s*prompt\s*>/i,
    /<\|im\s*instruction\s*>/i,
    /<\|user\s*>/i,
    /<\|assistant\s*>/i,
    /<\|system\s*>/i,
    /####/,
    /```/,
    /---\s*$/,
    /\n\n\n/,
    /\[\]/,
    /\{\|\}/
  ].freeze

  def sanitize_text(text)
    return "" unless text
    ActionView::Helpers::TextHelper.strip_tags(text.to_s)[0...10_000]
  end

  def sanitize_prompt(text)
    return "" unless text

    sanitized = text.to_s
    PROMPT_INJECTION_PATTERNS.each { |p| sanitized = sanitized.gsub(p, "") }
    sanitized = sanitized.gsub(/[\r\n]+/, " ").gsub(/\s+/, " ").strip[0...8000]
  end

  def validate_upload(files)
    total_size = files.sum(&:size)
    return [false, "Total size exceeds #{MAX_TOTAL_SIZE / 1_048_576}MB"] if total_size > MAX_TOTAL_SIZE

    files.each do |file|
      extension = File.extname(file.filename.to_s).downcase
      unless FILE_ALLOWLIST.include?(extension)
        return [false, "File type '#{extension}' not allowed. Allowed: #{FILE_ALLOWLIST.join(', ')}"]
      end
      return [false, "File '#{file.filename}' exceeds #{MAX_FILE_SIZE / 1_048_576}MB"] if file.size > MAX_FILE_SIZE
    end

    [true, nil]
  end
end
