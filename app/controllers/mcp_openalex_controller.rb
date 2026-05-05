class McpOpenalexController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_authentication
  before_action :authenticate_api_request

  def create
    server = build_openalex_server
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(server)
    server.transport = transport

    status, headers, body = transport.handle_request(request)

    render json: body.first, status: status, headers: headers
  end

  private

  def authenticate_api_request
    # Check for API key in headers or params
    api_key = request.headers['Authorization']&.split('Bearer ')&.last || 
      params[:api_key]

    # For now, allow empty key for development
    # In production, implement proper validation:
    # if api_key.blank? || !valid_api_key?(api_key)
    #   render json: { error: "Unauthorized" }, status: :unauthorized
    #   return
    # end
  end

  def valid_api_key?(key)
    # Implement your API key validation logic
    # Example: ApiKey.exists?(key: key)
    true # Placeholder for development
  end

  private

  def build_openalex_server
    user_context = {}
    # user_context[:user_id] = current_user&.id if current_user

    MCP::Server.new(
      name: "openalex_server",
      title: "OpenAlex Scholarly API",
      version: OpenAlex::VERSION,
      instructions: "Access scholarly data from OpenAlex through structured tools",
      tools: openalex_tools,
      server_context: user_context
    )
  end

  def openalex_tools
    [
      OpenAlexTools::SearchAuthorsTool,
      OpenAlexTools::GetAuthorWorksTool,
      OpenAlexTools::GetWorkByDoiTool,
      OpenAlexTools::SearchWorksTool,
      OpenAlexTools::SearchSourcesTool,
      OpenAlexTools::GetSourceWorksTool,
      OpenAlexTools::SearchInstitutionsTool,
      OpenAlexTools::GetInstitutionWorksTool,
      OpenAlexTools::SearchTopicsTool,
      OpenAlexTools::GetTopicWorksTool,
      OpenAlexTools::SearchPublishersTool,
      OpenAlexTools::GetPublisherWorksTool,
      OpenAlexTools::SearchFundersTool,
      OpenAlexTools::GetFunderWorksTool,
      OpenAlexTools::GetAuthorComprehensiveWorksTool
    ]
  end
end
