module ApplicationHelper
  def registrations_allowed?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("REGISTRATIONS_ALLOWED", true))
  end
end
