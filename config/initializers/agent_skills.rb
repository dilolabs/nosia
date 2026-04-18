Rails.application.config.agent_skills = ActiveSupport::OrderedOptions.new
Rails.application.config.agent_skills.enabled = ENV.fetch("AGENT_SKILLS_ENABLED", "true") == "true"
Rails.application.config.agent_skills.max_file_size = ENV.fetch("AGENT_SKILLS_MAX_FILE_SIZE", "1048576").to_i
Rails.application.config.agent_skills.timeout = ENV.fetch("AGENT_SKILLS_TIMEOUT", "30").to_i

# Eager load agent skills in development
if Rails.env.development? || Rails.env.test?
  Dir.glob(Rails.root.join("app/models/agent_skills/**/*.rb")).each do |file|
    require_dependency file
  end
end
