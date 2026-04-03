module OpenAlex
  module Entities
    class Institution
      attr_reader :id, :display_name, :ror, :country_code, :works_count, :cited_by_count

      def initialize(data)
        if data.is_a?(Hash) && data.key?('id')
          @id = data['id']
          @display_name = data['display_name']
          @ror = data['ror']
          @country_code = data['country_code']
          @works_count = data['works_count']
          @cited_by_count = data['cited_by_count']
        elsif data.is_a?(Hash) && data[:id]
          @id = data[:id]
          @display_name = nil
          @ror = nil
          @country_code = nil
          @works_count = nil
          @cited_by_count = nil
        else
          @id = data
          @display_name = nil
          @ror = nil
          @country_code = nil
          @works_count = nil
          @cited_by_count = nil
        end
      end

      def self.search(name)
        client = OpenAlex::ApiClient.new
        response = client.get("/institutions", search: name)
        response['results'].map { |result| new(result) }
      end

      def self.find_by_ror(ror)
        client = OpenAlex::ApiClient.new
        response = client.get("/institutions", filter: "ror:#{ror}")
        new(response['results'].first) if response['results'].any?
      end

      def works
        return [] unless @id && !@id.empty?
        
        client = OpenAlex::ApiClient.new
        response = client.get("/works", filter: "authorships.institutions.id:#{@id}")
        response['results'].map { |result| OpenAlex::Entities::Work.new(result) }
      end
    end
  end
end