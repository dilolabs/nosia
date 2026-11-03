class Nosia::NativeReadinessesController < ActionController::Base
  before_action :authenticate_native_installation

  def show
    ActiveRecord::Base.connection.execute("SELECT 1")
    if SolidQueue::Process.where(kind: "Worker").where("last_heartbeat_at > ?", 2.minutes.ago).exists?
      head :ok
    else
      head :service_unavailable
    end
  rescue ActiveRecord::ActiveRecordError
    head :service_unavailable
  end

  private
    def authenticate_native_installation
      key = ENV.fetch("AI_API_KEY", "")
      unless Nosia::NativeStack.enabled? && !key.empty? &&
          ActiveSupport::SecurityUtils.secure_compare(request.authorization.to_s, "Bearer #{key}")
        head :unauthorized
      end
    end
end
