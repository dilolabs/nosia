class GreenIt::RecountJob < ApplicationJob
  queue_as :background

  def perform
    Chat.find_each(&:recount!)
    Account.find_each(&:recount!)
  end
end
