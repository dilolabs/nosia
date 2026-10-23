require "test_helper"
require_relative "../support/localized_view_assertions"

class ViewCopyTest < ActiveSupport::TestCase
  include LocalizedViewAssertions

  test "shell and authentication sources have no uncatalogued UI literals" do
    assert_localized_view_sources Dir.glob(Rails.root.join("app/views/{application,layouts,static,sessions,users,first_runs}/**/*.erb"))
  end
end
