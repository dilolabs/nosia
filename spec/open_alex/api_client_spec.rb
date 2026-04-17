require 'rails_helper'

RSpec.describe OpenAlex::ApiClient do
  let(:config) { OpenAlex::Configuration.new }
  let(:client) { described_class.new(config) }

  describe '#get' do
    it 'makes authenticated requests' do
      stub_request(:get, "https://api.openalex.org/works")
        .with(query: { api_key: config.api_key })
        .to_return(status: 200, body: '{"results":[]}')

      response = client.get('/works')
      expect(response).to eq({"results" => []})
    end

    it 'handles rate limiting with retry' do
      stub_request(:get, "https://api.openalex.org/works")
        .to_return({ status: 429 }, { status: 200, body: '{"results":[]}' })

      response = client.get('/works')
      expect(response).to eq({"results" => []})
    end
  end
end