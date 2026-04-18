require "test_helper"

class AgentSkill::ParserTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "test@example.com", password: "testpassword123")
    @account = Account.create!(name: "Test Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  test "parses valid SKILL.md with frontmatter" do
    agent_skill = @account.agent_skills.new
    agent_skill.skill_md.attach(
      io: StringIO.new("---\nname: test-skill\ndescription: Test description\n---\n\n# Instructions"),
      filename: "SKILL.md",
      content_type: "text/markdown"
    )
    agent_skill.save!

    assert_equal "test-skill", agent_skill.name
    assert_equal "Test description", agent_skill.description
  end

  test "parses SKILL.md without frontmatter" do
    agent_skill = @account.agent_skills.new(name: "manual-name")
    agent_skill.skill_md.attach(
      io: StringIO.new("# Instructions"),
      filename: "SKILL.md",
      content_type: "text/markdown"
    )
    agent_skill.save!

    assert_equal "manual-name", agent_skill.name
    assert_equal "# Instructions", agent_skill.description
  end
end
