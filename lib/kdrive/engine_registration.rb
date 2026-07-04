module Kdrive
  class EngineRegistration < Engines::Registration
    def initialize
      super(
        id: "kdrive",
        name: "Infomaniak kDrive",
        icon: "📁",
        description: "Search, browse and read files from your Infomaniak kDrive.",
        required_config: [
          { name: "token", label: "kDrive Token", type: "secret", required: true },
          { name: "drive_id", label: "kDrive ID", type: "string", required: true }
        ],
        tool_classes: KdriveTools.all,
        health_check: ->(auth) { Kdrive::ApiClient.new(auth).ping || raise("kDrive unreachable") },
        capabilities: [ "tools" ]
      )
    end
  end
end
