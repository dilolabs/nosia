module OpenAlex
  class Tool
    # Authors
    def self.search_authors(name)
      authors = OpenAlex::Entities::Author.search(name)
      authors.map { |author| {
        id: author.id,
        name: author.display_name,
        works_count: author.works_count,
        cited_by_count: author.cited_by_count
      } }
    end

    def self.get_author_works(author_id)
      author = OpenAlex::Entities::Author.new(id: author_id)
      author.works.map { |work| {
        id: work.id,
        doi: work.doi,
        title: work.title,
        publication_year: work.publication_year,
        cited_by_count: work.cited_by_count,
        is_open_access: work.is_oa
      } }
    end

    # Works
    def self.get_work_by_doi(doi)
      work = OpenAlex::Entities::Work.find_by_doi(doi)
      return nil unless work

      {
        id: work.id,
        doi: work.doi,
        title: work.title,
        publication_year: work.publication_year,
        cited_by_count: work.cited_by_count,
        is_open_access: work.is_oa
      }
    end

    def self.search_works(query, params = {})
      client = OpenAlex::ApiClient.new
      response = client.get("/works", params.merge(search: query))
      response['results'].map { |result| {
        id: result['id'],
        doi: result['doi'],
        title: result['title'],
        year: result['publication_year'],
        citations: result['cited_by_count']
      } }
    end

    # Sources (Journals)
    def self.search_sources(name)
      sources = OpenAlex::Entities::Source.search(name)
      sources.map { |source| {
        id: source.id,
        name: source.display_name,
        issn: source.issn,
        publisher: source.publisher,
        works_count: source.works_count
      } }
    end

    def self.get_source_works(source_id)
      source = OpenAlex::Entities::Source.new(id: source_id)
      source.works.map { |work| {
        id: work.id,
        title: work.title,
        year: work.publication_year,
        citations: work.cited_by_count
      } }
    end

    # Institutions
    def self.search_institutions(name)
      institutions = OpenAlex::Entities::Institution.search(name)
      institutions.map { |institution| {
        id: institution.id,
        name: institution.display_name,
        ror: institution.ror,
        country: institution.country_code,
        works_count: institution.works_count
      } }
    end

    def self.get_institution_works(institution_id)
      institution = OpenAlex::Entities::Institution.new(id: institution_id)
      institution.works.map { |work| {
        id: work.id,
        title: work.title,
        year: work.publication_year,
        citations: work.cited_by_count
      } }
    end

    # Topics
    def self.search_topics(name)
      topics = OpenAlex::Entities::Topic.search(name)
      topics.map { |topic| {
        id: topic.id,
        name: topic.display_name,
        domain: topic.domain,
        field: topic.field,
        subfield: topic.subfield,
        works_count: topic.works_count
      } }
    end

    def self.get_topic_works(topic_id)
      topic = OpenAlex::Entities::Topic.new(id: topic_id)
      topic.works.map { |work| {
        id: work.id,
        title: work.title,
        year: work.publication_year,
        citations: work.cited_by_count
      } }
    end

    # Publishers
    def self.search_publishers(name)
      publishers = OpenAlex::Entities::Publisher.search(name)
      publishers.map { |publisher| {
        id: publisher.id,
        name: publisher.display_name,
        works_count: publisher.works_count,
        cited_by_count: publisher.cited_by_count
      } }
    end

    def self.get_publisher_works(publisher_id)
      publisher = OpenAlex::Entities::Publisher.new(id: publisher_id)
      publisher.works.map { |work| {
        id: work.id,
        title: work.title,
        year: work.publication_year,
        citations: work.cited_by_count
      } }
    end

    # Funders
    def self.search_funders(name)
      funders = OpenAlex::Entities::Funder.search(name)
      funders.map { |funder| {
        id: funder.id,
        name: funder.display_name,
        works_count: funder.works_count,
        cited_by_count: funder.cited_by_count
      } }
    end

    def self.get_funder_works(funder_id)
      funder = OpenAlex::Entities::Funder.new(id: funder_id)
      funder.works.map { |work| {
        id: work.id,
        title: work.title,
        year: work.publication_year,
        citations: work.cited_by_count
      } }
    end
  end
end