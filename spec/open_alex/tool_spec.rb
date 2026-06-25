require 'rails_helper'

RSpec.describe OpenAlex::Tool do
  describe '.search_authors' do
    it 'searches authors by name' do
      stub_request(:get, "https://api.openalex.org/authors")
        .with(query: { search: "Einstein", api_key: anything })
        .to_return(status: 200, body: '{"results":[{"id":"A1","display_name":"Albert Einstein","works_count":100,"cited_by_count":5000}]}')

      results = described_class.search_authors("Einstein")
      expect(results.first[:name]).to eq("Albert Einstein")
    end
  end

  describe '.get_work_by_doi' do
    it 'finds work by DOI' do
      stub_request(:get, "https://api.openalex.org/works")
        .with(query: { filter: "doi:10.1234/test", api_key: anything })
        .to_return(status: 200, body: '{"results":[{"id":"W1","doi":"10.1234/test","title":"Test Work","publication_year":2024,"cited_by_count":10,"is_oa":true}]}')

      work = described_class.get_work_by_doi("10.1234/test")
      expect(work[:title]).to eq("Test Work")
    end
  end
end