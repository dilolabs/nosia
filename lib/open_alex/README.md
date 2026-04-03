# OpenAlex Rails Engine

Rails engine for integrating OpenAlex scholarly API into Nosia.

## Installation

Add to your Gemfile:

```ruby
gem 'open_alex', path: 'path/to/this/engine'
```

Then run:

```bash
bundle install
```

## Configuration

Set your API key in environment:

```bash
export OPENALEX_API_KEY='your_api_key_from_openalex.org'
```

Or configure in initializer:

```ruby
# config/initializers/open_alex.rb
OpenAlex.configure do |config|
  config.api_key = ENV['OPENALEX_API_KEY']
  config.base_url = 'https://api.openalex.org'
  config.max_retries = 5
  config.timeout = 30
end
```

## Usage

### Tool Interface

The engine provides a comprehensive tool interface for all OpenAlex entities:

#### Authors
```ruby
# Search authors
authors = OpenAlex::Tool.search_authors("Einstein")
# => [{id: "A1", name: "Albert Einstein", works_count: 100, cited_by_count: 5000}]

# Get author's works
author_works = OpenAlex::Tool.get_author_works("A1")
# => [{id: "W1", title: "Work 1", year: 2024, citations: 10}]
```

#### Works
```ruby
# Get work by DOI
work = OpenAlex::Tool.get_work_by_doi("10.1234/test")
# => {id: "W1", doi: "10.1234/test", title: "Test Work", ...}

# Search works
works = OpenAlex::Tool.search_works("quantum computing", per_page: 50)
# => [{id: "W1", doi: "10.xxxx", title: "...", year: 2024, citations: 42}]
```

#### Sources (Journals)
```ruby
# Search sources (journals)
sources = OpenAlex::Tool.search_sources("Nature")
# => [{id: "S1", name: "Nature", issn: "0028-0836", publisher: "Springer Nature", works_count: 100000}]

# Get source's works
source_works = OpenAlex::Tool.get_source_works("S1")
# => [{id: "W1", title: "Article", year: 2024, citations: 100}]
```

#### Institutions
```ruby
# Search institutions
institutions = OpenAlex::Tool.search_institutions("MIT")
# => [{id: "I1", name: "Massachusetts Institute of Technology", ror: "04wxnsj24", country: "US", works_count: 50000}]

# Get institution's works
institution_works = OpenAlex::Tool.get_institution_works("I1")
# => [{id: "W1", title: "Paper", year: 2024, citations: 50}]
```

#### Topics
```ruby
# Search topics
topics = OpenAlex::Tool.search_topics("machine learning")
# => [{id: "T1", name: "Machine learning", domain: "Computer Science", field: "Artificial Intelligence", subfield: "Machine Learning", works_count: 10000}]

# Get topic's works
topic_works = OpenAlex::Tool.get_topic_works("T1")
# => [{id: "W1", title: "ML Paper", year: 2024, citations: 25}]
```

#### Publishers
```ruby
# Search publishers
publishers = OpenAlex::Tool.search_publishers("Elsevier")
# => [{id: "P1", name: "Elsevier", works_count: 1000000, cited_by_count: 5000000}]

# Get publisher's works
publisher_works = OpenAlex::Tool.get_publisher_works("P1")
# => [{id: "W1", title: "Published Work", year: 2024, citations: 15}]
```

#### Funders
```ruby
# Search funders
funders = OpenAlex::Tool.search_funders("NSF")
# => [{id: "F1", name: "National Science Foundation", works_count: 250000, cited_by_count: 1000000}]

# Get funder's works
funder_works = OpenAlex::Tool.get_funder_works("F1")
# => [{id: "W1", title: "Funded Research", year: 2024, citations: 30}]
```

### Direct API Access

```ruby
client = OpenAlex::ApiClient.new

# Custom queries with full control
response = client.get("/works", {
  filter: "publication_year:2024,is_oa:true",
  sort: "cited_by_count:desc",
  per_page: 100
})
```

### Entity Models

```ruby
# Works
work = OpenAlex::Entities::Work.find_by_doi("10.1234/test")
puts work.title

# Authors
authors = OpenAlex::Entities::Author.search("Einstein")
author = OpenAlex::Entities::Author.new(id: "A1")
works = author.works

# Sources (Journals)
sources = OpenAlex::Entities::Source.search("Nature")
source = OpenAlex::Entities::Source.find_by_issn("0028-0836")
works = source.works

# Institutions
institutions = OpenAlex::Entities::Institution.search("MIT")
institution = OpenAlex::Entities::Institution.new(id: "I1")
works = institution.works

# Topics
topics = OpenAlex::Entities::Topic.search("machine learning")
topic = OpenAlex::Entities::Topic.new(id: "T1")
works = topic.works

# Publishers
publishers = OpenAlex::Entities::Publisher.search("Elsevier")
publisher = OpenAlex::Entities::Publisher.new(id: "P1")
works = publisher.works

# Funders
funders = OpenAlex::Entities::Funder.search("NSF")
funder = OpenAlex::Entities::Funder.new(id: "F1")
works = funder.works
```

## Features

- ✅ **Complete OpenAlex API coverage** - All 6 entity types
- ✅ **API key authentication** with environment variable support
- ✅ **Automatic retry** with exponential backoff for rate limits
- ✅ **Entity models** for all OpenAlex entities (Works, Authors, Sources, Institutions, Topics, Publishers, Funders)
- ✅ **Comprehensive tool interface** - 14 methods for Nosia integration
- ✅ **Two-step ID lookup pattern** following OpenAlex best practices
- ✅ **Error handling** for rate limits and API errors
- ✅ **Flexible initialization** - supports ID-only, full data, and symbol keys
- ✅ **Faraday-based HTTP client** - lightweight and Rails-friendly

## Testing

Run tests with:

```bash
bundle exec rspec spec/open_alex/
```

## API Documentation

See [OpenAlex API Docs](https://docs.openalex.org) for full API reference.

## License

MIT License - see LICENSE file.