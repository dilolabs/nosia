module ApplicationHelper
  def registrations_allowed?
    ActiveModel::Type::Boolean.new.cast(ENV["REGISTRATIONS_ALLOWED"])
  end
end
