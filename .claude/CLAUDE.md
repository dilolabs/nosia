# 37signals Rails Configuration

## Tech Stack

- **Ruby** 3.3, **Rails** 8.2 (edge), **MySQL** (SaaS) / **SQLite** (OSS)
- **Frontend:** Hotwire (Turbo 8 + Stimulus 3.2), Importmap (no Node.js)
- **Testing:** Minitest + Fixtures (not RSpec, not FactoryBot)
- **Auth:** Custom passwordless: passkeys (WebAuthn) + magic links (no Devise), `has_secure_password` optional
- **Background Jobs:** Solid Queue (database-backed, no Redis)
- **Caching:** Solid Cache | **WebSockets:** Solid Cable
- **IDs:** UUIDv7 everywhere (base36-encoded, 25-char strings)
- **Assets:** Propshaft + Import Maps (no Node.js, no Webpack)
- **Deployment:** Kamal 2 + Thruster

## Architecture

```
app/
  controllers/     # Thin. Only 7 REST actions. New resource for each state change.
  models/          # Rich. Business logic, concerns, associations, validations.
  models/concerns/ # Horizontal behavior: Closeable, Assignable, Searchable.
  views/           # ERB + Turbo Frames/Streams. No JS frameworks.
  jobs/            # Shallow. Call model methods, don't contain logic.
  mailers/         # Minimal. Bundle notifications, plain-text first.
  channels/        # ActionCable channels for real-time.
```

**No `app/services/`, `app/queries/`, `app/policies/`, `app/forms/` directories.** Business logic lives in models. Authorization via roles on User model + controller concerns. Complex forms use standard Rails nested attributes.

## Core Philosophy

- **Vanilla Rails:** Rich domain models, thin controllers, avoid service objects (acceptable when justified, but not as default architecture), no Devise, no Pundit
- **Everything is CRUD:** State changes = new resources (`Closure`, `Publication`, `Archival`)
- **State as records:** No boolean flags for business state -- use `has_one` state records
- **Rich models over services:** Business logic lives in models, organized via concerns
- **Concerns for organization:** Models compose behavior via focused concerns (`Closeable`, `Assignable`)
- **No foreign key constraints:** Application enforces referential integrity
- **Multi-tenancy:** URL path-based (`/:account_id/...`), `account_id` on every table
- **Current for context:** `Current.user`, `Current.account`, `Current.session`
- **Shallow jobs:** `_later`/`_now` pattern; job calls model method, logic stays in model

## Key Commands

```bash
bin/setup                                    # Initial setup
bin/dev                                      # Start dev server
bin/rails test                               # Full test suite
bin/rails test test/models/card_test.rb      # Specific file
bin/rails test test/models/card_test.rb:14   # Specific line
bin/rails test:system                        # System tests (Capybara + Selenium)
bin/ci                                       # Full CI (rubocop + brakeman + tests)
bundle exec rubocop -a                       # Auto-fix Ruby style
bin/rails db:migrate                         # Run migrations
bin/rails db:fixtures:load                   # Load fixture data
bin/rails db:reset                           # Drop, create, load schema + fixtures
```

## Development Workflow

1. Write a failing Minitest test with fixtures
2. Implement minimal code to make it pass
3. Refactor while tests stay green

## Naming Conventions

| Layer | Pattern | Example |
|-------|---------|---------|
| Model | Singular PascalCase | `Card`, `BoardPublication` |
| Controller | Plural, nested by resource | `Cards::ClosuresController` |
| State Record | Noun describing state | `Closure`, `Publication`, `Goldness` |
| Concern | Adjective/-able | `Closeable`, `Assignable`, `Searchable` |
| Job | `Model::VerbJob` | `Event::RelayJob`, `Card::CleanupJob` |
| Test | `ModelTest` / `ControllerTest` | `CardTest`, `Cards::ClosuresControllerTest` |

## Style Guide (37signals)

- Expanded conditionals over guard clauses (exception: single-line early returns at method start)
- Method ordering: class methods > public instance (`initialize` first) > private
- Order private methods by invocation flow (call order)
- Bang methods (`!`) only when a non-bang counterpart exists
- No newline under `private`/`protected` keyword; indent content under it
- Avoid service objects -- domain logic belongs in models with concerns (services acceptable when justified)
- `belongs_to :creator, default: -> { Current.user }` for context defaults
- `touch: true` on child associations for cache invalidation

# Rails Development Principles (2026)

A comprehensive guide to modern development principles applied to Ruby on Rails applications. Covers universal software principles, Rails-specific philosophy, architecture patterns, testing strategy, security, and performance.

---

## Table of Contents

1. [Universal Software Principles](#1-universal-software-principles)
2. [The Rails Doctrine](#2-the-rails-doctrine)
3. [Modern Rails 8 Stack](#3-modern-rails-8-stack)
4. [Architecture & Code Organization](#4-architecture--code-organization)
5. [Testing Strategy](#5-testing-strategy)
6. [Security Principles](#6-security-principles)
7. [Performance Principles](#7-performance-principles)
8. [Settled Debates](#8-settled-debates)
9. [Anti-Patterns to Avoid](#9-anti-patterns-to-avoid)

---

## 1. Universal Software Principles

### KISS -- Keep It Simple

Every piece of code should be as simple as possible. There is no value in a "smart" solution -- only in an easily understandable one.

In Rails, this means:
- Standard CRUD controllers with conventional routing
- No abstractions until complexity actually demands them
- Prefer `rails generate scaffold` over hand-rolled architectures
- If a junior developer can't understand it in 30 seconds, simplify it

DHH's Rails World 2025 keynote was explicitly a "call for radical simplicity." The industry has built unnecessarily complicated solutions around fundamentally simple CRUD operations.

### DRY -- Don't Repeat Yourself

Every piece of knowledge must have a single, authoritative representation.

Rails enforces this via:
- Schema-derived migrations (database is the source of truth)
- Convention-based naming (`User` model -> `users` table -> `UsersController` -> `/users` routes)
- Concerns for shared model behavior
- Partials and ViewComponents for shared UI
- Service objects for shared business logic

**Caveat:** DRY is about knowledge, not code. Three similar lines are better than a premature abstraction. Duplicate code is cheaper than the wrong abstraction.

### YAGNI -- You Ain't Gonna Need It

Implement only what is currently required.

- Don't introduce service objects until a controller action exceeds ~10 lines of business logic
- Don't create microservices until the monolith proves insufficient
- Don't add configuration options for hypothetical future requirements
- Don't build abstractions for one-time operations

The right amount of complexity is the minimum needed for the current task. Start simple, extract later.

### SOLID

**Single Responsibility Principle (SRP)**
Each class has one reason to change. A model handles persistence, a service handles business logic, a controller handles HTTP.

```ruby
# BAD: Model does everything
class Order < ApplicationRecord
  def process_payment     # payment logic
  def send_confirmation   # email logic
  def update_inventory    # inventory logic
end

# GOOD: Each class has one job
class Order < ApplicationRecord
  # validations, associations, scopes only
end

class ProcessOrder
  def call(order)
    PaymentService.charge(order)
    OrderMailer.confirmation(order).deliver_later
    InventoryService.update(order)
  end
end
```

**Open/Closed Principle (OCP)**
Open for extension, closed for modification. Add new behavior via inheritance, modules, or composition.

```ruby
# Add new behavior without modifying existing code
module Trackable
  extend ActiveSupport::Concern
  included do
    has_many :activities, as: :trackable
    after_create :track_creation
  end
end
```

**Liskov Substitution Principle (LSP)**
Subclasses must be usable wherever the parent class is expected. STI subclasses should not break parent behavior.

**Interface Segregation Principle (ISP)**
No client should depend on methods it does not use. In Ruby, use focused concerns and modules rather than god objects.

**Dependency Inversion Principle (DIP)**
High-level modules should not depend on low-level modules. Both depend on abstractions.

```ruby
# BAD: Hard-coded dependency
class OrderProcessor
  def call(order)
    StripeGateway.new.charge(order.total)
  end
end

# GOOD: Injected dependency
class OrderProcessor
  def initialize(gateway: StripeGateway.new)
    @gateway = gateway
  end

  def call(order)
    @gateway.charge(order.total)
  end
end
```

### Separation of Concerns

Each component handles one aspect of the system. Rails MVC is the primary expression:

| Layer | Responsibility |
|-------|---------------|
| Controller | HTTP handling, parameter validation, response rendering |
| Model | Data persistence, validations, associations, simple domain logic |
| View | Presentation markup |
| Service | Multi-step business operations |
| Query | Complex database queries |
| Policy | Authorization rules |
| Presenter | Display formatting |
| Component | Reusable UI elements |

### Single Source of Truth

Every piece of data or logic lives in exactly one place.

- Database schema is the source of truth for data structure
- `db/schema.rb` reflects the current database state
- Validations live on the model, not duplicated in controllers
- Business rules live in services, not scattered across callbacks
- Authorization rules live in policies, not spread across controllers

### Principle of Least Surprise

Software behavior should match developer expectations. Rails Convention over Configuration is a direct expression:

- `User` model maps to `users` table
- `UsersController` handles `/users` routes
- `user_path(@user)` generates `/users/1`
- `app/models/user.rb` is where `User` lives

When your code surprises experienced Rails developers, reconsider.

---

## 2. The Rails Doctrine

### The Nine Pillars

1. **Optimize for programmer happiness** -- Developer experience matters. Ruby's expressiveness and Rails' conventions serve this goal.
2. **Convention over Configuration** -- Naming conventions, directory structure, and sensible defaults eliminate boilerplate.
3. **The menu is omakase** -- Rails ships a curated, opinionated stack. Trust the framework's choices.
4. **No one paradigm** -- Use OOP, functional patterns, metaprogramming -- whatever fits the problem.
5. **Exalt beautiful code** -- Code is read far more than written. Readability is a feature.
6. **Provide sharp knives** -- Trust developers with powerful tools rather than restricting them.
7. **Value integrated systems** -- A full-stack framework beats a collection of libraries.
8. **Progress over stability** -- Rails evolves. Embrace change over backwards compatibility.
9. **Push up a big tent** -- The community is diverse. There's room for different approaches.

### The Majestic Monolith

DHH's position in 2025 is stronger than ever:

> "The majestic monolith remains undefeated for the vast majority of web apps. Replacing method calls with network calls makes everything harder, slower, and more brittle. It should be the absolute last resort."

Even GitHub and Shopify run monoliths with millions of lines of code. The 2025 industry trend shows enterprises returning from microservices to modular monoliths.

**When the monolith works (almost always):**
- Method calls are ~1000x faster than network calls
- Shared database transactions are trivial
- Refactoring is IDE-assisted, not cross-service negotiation
- Debugging follows a single stack trace
- Deployment is one unit

**When to extract (rarely):**
- A component has fundamentally different scaling needs (e.g., video transcoding)
- Team size exceeds ~50 engineers on the same codebase
- Regulatory isolation is required

### "We're All CRUD Monkeys"

DHH openly states: "I'm a CRUD monkey. My career is CRUD monkeying." Most web applications are fundamentally CRUD operations with varying levels of business logic. Embrace this reality rather than adding complexity to avoid it.

---

## 3. Modern Rails 8 Stack

### The Omakase Stack (2026)

| Layer | Tool | Replaces |
|-------|------|----------|
| Frontend | Hotwire (Turbo + Stimulus) | React, Vue, Angular |
| Background Jobs | Solid Queue | Sidekiq + Redis |
| Caching | Solid Cache | Redis |
| WebSockets | Solid Cable | Redis |
| Asset Pipeline | Propshaft + Import Maps | Webpack, esbuild |
| Deployment | Kamal 2 + Thruster | Heroku, Capistrano |
| CSS | Tailwind CSS | Bootstrap, custom CSS |
| Components | ViewComponent | Partials |

### Hotwire-First Development

Build reactive UIs via server-rendered HTML rather than heavy JavaScript frameworks:

- **Turbo Drive**: SPA-like page transitions without JavaScript
- **Turbo Frames**: Partial page updates by scoping navigation to frames
- **Turbo Streams**: Real-time updates via WebSocket or HTTP responses
- **Stimulus**: Modest JavaScript behaviors attached to HTML via data attributes

Rule: reach for Turbo Frames before Stimulus, Stimulus before custom JavaScript, and never for a JavaScript framework.

### The Solid Trifecta

Rails 8 eliminates Redis as a dependency:

- **Solid Queue**: Database-backed job processing. Supports priorities, concurrency controls, recurring jobs. Production-tested at 37signals.
- **Solid Cache**: Database-backed caching with FIFO eviction. Leverages NVMe SSDs -- fast enough for most applications.
- **Solid Cable**: Database-backed Action Cable adapter. Good enough for most WebSocket use cases.

Benefit: one fewer infrastructure dependency, simpler deployment, easier development setup.

### No Build Philosophy

- **Propshaft**: Simple asset pipeline, no compilation step
- **Import Maps**: Pin JavaScript dependencies without bundling
- **No Node.js required**: The entire Rails stack runs on Ruby alone

### Kamal 2 Deployment

- Zero-downtime deploys over HTTP/2 with SSL
- Thruster proxy handles compression, caching, SSL termination
- Docker-based, cloud-agnostic (runs on any Linux server)
- "No PaaS required" -- deploy to $5/month VPS or $300 mini-PCs

### Rails 8.1 Additions

- Native Markdown rendering
- Active Job Continuations (pausable background tasks)
- Local CI testing
- Turbo Offline support
- Action Push (push notifications)

---

## 4. Architecture & Code Organization

### The Layer Cake

```
HTTP Request
    |
    v
[Controller]     Thin. Delegates to services. Renders responses.
    |
    v
[Service]        Business logic. Orchestrates models, APIs, side effects.
    |
    +---> [Query]     Complex reads. Returns scopes or arrays.
    +---> [Policy]    Authorization. Returns true/false.
    +---> [Form]      Multi-model validation. Returns valid/invalid.
    |
    v
[Model]          Persistence. Validations. Associations. Simple logic.
    |
    v
[Database]
```

For the view layer:

```
[Controller]
    |
    v
[View/Template]  ERB markup only. No logic.
    |
    +---> [Presenter]     Format data for display.
    +---> [Component]     Reusable UI element with tests.
    +---> [Helper]        Simple view utilities (use sparingly).
```

### Directory Structure

```
app/
  controllers/     # HTTP handling, thin
  models/          # ActiveRecord, persistence, validations
  views/           # ERB templates, no logic
  services/        # Business logic, orchestration
  queries/         # Complex database queries
  forms/           # Multi-model form objects
  policies/        # Pundit authorization
  presenters/      # View formatting (SimpleDelegator)
  components/      # ViewComponents (reusable UI)
  jobs/            # Background jobs (Solid Queue)
  mailers/         # Email delivery
```

### When to Extract

| Pattern | Extract When | Don't Extract When |
|---------|-------------|-------------------|
| Service Object | Controller action exceeds ~10 lines of business logic, logic spans multiple models, external API calls, needs isolated testing | Simple CRUD, single-model operations, logic fits naturally in the model |
| Query Object | Query joins multiple tables, has conditional clauses, is reused across controllers | Single-table scope, one-liner query |
| Form Object | Form touches multiple models, has custom validation logic, wizard/multi-step forms | Single-model form, standard validations |
| Presenter | Model has display formatting methods, conditional display logic | Simple attribute display |
| ViewComponent | UI element is reused across views, needs unit testing, has complex markup | One-off view snippet |
| Concern | Behavior is shared across multiple models, is simple and narrowly focused | Logic belongs to one model, complex behavior |
| Policy | Authorization logic, role-based access | No access control needed |

### Skinny Everything

The original "Skinny Controllers, Fat Models" mantra has evolved. The 2025 consensus is **Skinny Everything**:

```ruby
# Controller: thin, delegates
class OrdersController < ApplicationController
  def create
    result = CreateOrder.call(order_params, current_user)
    if result.success?
      redirect_to result.order, notice: "Order placed"
    else
      @order = result.order
      render :new, status: :unprocessable_entity
    end
  end
end

# Service: focused business logic
class CreateOrder
  def self.call(params, user)
    order = user.orders.build(params)
    return Result.failure(order) unless order.valid?

    order.save!
    ProcessPaymentJob.perform_later(order)
    Result.success(order)
  end
end

# Model: persistence and domain rules
class Order < ApplicationRecord
  belongs_to :user
  has_many :line_items, dependent: :destroy

  validates :total, numericality: { greater_than: 0 }

  scope :recent, -> { where("created_at > ?", 30.days.ago) }
end
```

### Service Object Pattern

```ruby
class CreateOrder
  Result = Data.define(:success?, :order, :errors)

  def self.call(...)
    new(...).call
  end

  def initialize(params, user)
    @params = params
    @user = user
  end

  def call
    order = @user.orders.build(@params)

    if order.save
      notify(order)
      Result.new(success?: true, order: order, errors: [])
    else
      Result.new(success?: false, order: order, errors: order.errors.full_messages)
    end
  end

  private

  def notify(order)
    OrderMailer.confirmation(order).deliver_later
  end
end
```

Key conventions:
- `.call` class method as the public interface
- Return a Result object (success/failure + data)
- One public method per service
- Private methods for sub-steps
- Inject dependencies for testability

### Query Object Pattern

```ruby
class ActiveUsersQuery
  def initialize(relation = User.all)
    @relation = relation
  end

  def call(since: 30.days.ago)
    @relation
      .joins(:sessions)
      .where(sessions: { created_at: since.. })
      .distinct
      .order(last_sign_in_at: :desc)
  end
end

# Usage
ActiveUsersQuery.new.call(since: 7.days.ago)
ActiveUsersQuery.new(User.admin).call  # composable
```

---

## 5. Testing Strategy

### The Testing Pyramid

```
        /  System  \          Few: complete user workflows
       /  (Capybara) \        Slow, expensive, high confidence
      /________________\
     /    Integration    \    Some: HTTP request/response cycles
    /    (Request Specs)  \   Medium speed, good coverage
   /______________________\
  /        Unit Tests        \  Many: models, services, policies
 /   (Model, Service Specs)   \  Fast, focused, cheap
/______________________________\
```

### What to Test

| Layer | Test Type | What to Assert |
|-------|-----------|---------------|
| Model | Unit | Validations, associations, scopes, instance methods |
| Service | Unit | Success/failure paths, side effects, edge cases |
| Controller | Request | HTTP status, redirects, flash, response body |
| Policy | Unit | Every action for every role |
| Query | Unit | Correct results, edge cases, empty states |
| Component | Unit | Rendered HTML, slots, variants |
| Mailer | Unit | Recipients, subject, body content |
| Job | Unit | Enqueuing, idempotency, error handling |
| System | Integration | Critical user journeys only |

### Red-Green-Refactor

1. **RED**: Write a failing test that describes the desired behavior
2. **GREEN**: Write the minimum code to make the test pass
3. **REFACTOR**: Improve the code structure while keeping tests green

```ruby
# 1. RED: Write the failing test
RSpec.describe CreateOrder do
  it "creates an order and enqueues confirmation email" do
    user = create(:user)
    params = attributes_for(:order)

    result = described_class.call(params, user)

    expect(result).to be_success
    expect(result.order).to be_persisted
    expect(OrderMailer).to have_enqueued_mail(:confirmation)
  end
end

# 2. GREEN: Write minimal implementation
# 3. REFACTOR: Clean up while tests stay green
```

### Testing Principles

- **Test behavior, not implementation**: Assert what the code does, not how
- **One assertion per concept**: Each test verifies one behavior
- **Arrange-Act-Assert**: Clear structure in every test
- **Factory over fixture**: Use FactoryBot for flexible test data
- **Avoid `let!`**: Prefer explicit setup in each test for clarity
- **Test boundaries**: Validate at system edges (user input, API responses), trust internal code

### What NOT to Test

- Framework behavior (Rails validations work -- test your validation rules, not `validates`)
- Private methods (test via public interface)
- Trivial code (getters, delegations)
- Implementation details (which method was called, internal state)

---

## 6. Security Principles

### Defense in Depth

Apply multiple layers of security so that a breach in one layer is contained:

| Layer | Mechanism |
|-------|-----------|
| Input | Strong parameters, type coercion, allowlists |
| Authentication | `has_secure_password`, session management, rate limiting |
| Authorization | Pundit policies on every action |
| Output | Automatic HTML escaping, CSP headers |
| Data | Encryption at rest, encrypted credentials |
| Dependencies | Brakeman, bundler-audit in CI |
| Transport | HTTPS everywhere, HSTS headers |

### OWASP Top 10 for Rails

| Vulnerability | Rails Protection |
|--------------|-----------------|
| Injection (SQL, XSS) | Parameterized queries, automatic output escaping |
| Broken Authentication | `has_secure_password`, secure session config |
| Sensitive Data Exposure | `Rails.application.credentials`, encrypted attributes |
| XML External Entities | Disabled by default in Nokogiri |
| Broken Access Control | Pundit `authorize` on every action |
| Security Misconfiguration | `config.force_ssl`, secure defaults |
| Cross-Site Scripting (XSS) | Auto-escaping, `sanitize` helper, CSP |
| Insecure Deserialization | JSON over Marshal, strong parameters |
| Components with Vulnerabilities | `bundler-audit`, Dependabot |
| Insufficient Logging | `Rails.logger`, structured logging |

### Security Checklist

```ruby
# Every controller action
class PostsController < ApplicationController
  before_action :authenticate_user!        # Authentication

  def update
    @post = Post.find(params[:id])
    authorize @post                         # Authorization
    @post.update!(post_params)              # Strong parameters
  end

  private

  def post_params
    params.require(:post).permit(:title, :body)  # Allowlist
  end
end
```

### Automated Security Scanning

```bash
# Static analysis for Rails vulnerabilities
bundle exec brakeman --no-pager

# Known gem vulnerabilities
bundle exec bundler-audit check --update

# Both in CI, fail the build on warnings
```

---

## 7. Performance Principles

### The Performance Hierarchy

Fix in this order -- each level gives more impact per effort:

1. **N+1 queries** -- Biggest bang for the buck
2. **Missing indexes** -- Free performance
3. **Unnecessary queries** -- Counter caches, eager loading
4. **Caching** -- Fragment, Russian doll, low-level
5. **Background jobs** -- Move slow work out of the request
6. **Database optimization** -- Query tuning, read replicas
7. **Infrastructure** -- Vertical scaling, CDN, edge caching

### N+1 Prevention

```ruby
# BAD: N+1 query
@posts = Post.all
# In view: post.author.name triggers a query per post

# GOOD: Eager loading
@posts = Post.includes(:author)

# GOOD: Strict loading (raises on lazy load)
class Post < ApplicationRecord
  self.strict_loading_by_default = true
end
```

Use the **Bullet gem** to detect N+1 queries automatically in development and test.

### Caching Strategy

```ruby
# Fragment caching (most common)
<% cache @post do %>
  <%= render @post %>
<% end %>

# Russian doll caching (nested fragments)
<% cache @post do %>
  <% @post.comments.each do |comment| %>
    <% cache comment do %>
      <%= render comment %>
    <% end %>
  <% end %>
<% end %>

# Low-level caching (arbitrary data)
Rails.cache.fetch("stats/#{Date.current}", expires_in: 1.hour) do
  ExpensiveQuery.call
end

# Counter caches (avoid COUNT queries)
# In migration:
add_column :posts, :comments_count, :integer, default: 0
# In model:
belongs_to :post, counter_cache: true
```

### Database Optimization

```ruby
# Always index foreign keys
add_index :comments, :post_id

# Index columns used in WHERE, ORDER BY, JOIN
add_index :users, :email, unique: true
add_index :orders, [:user_id, :status]

# Use select to limit columns
User.select(:id, :name, :email)

# Use pluck for simple value arrays
User.where(active: true).pluck(:email)

# Use find_each for batch processing
User.find_each(batch_size: 1000) do |user|
  # processes in batches, not all at once
end
```

---

## 8. Settled Debates

### Concerns vs Service Objects

| | Concerns | Service Objects |
|--|---------|----------------|
| **Use for** | Simple shared model behavior | Multi-step business logic |
| **Examples** | `SoftDeletable`, `Searchable`, `Sluggable` | `CreateOrder`, `ProcessRefund` |
| **Scope** | Narrow, one behavior | Complete operation |
| **Testing** | Tested via including model | Tested in isolation |
| **Reuse** | Across models | Across controllers/jobs |

**Rule of thumb:** If the behavior is a property of the model (soft-delete, timestamps, search), use a concern. If it's an operation performed on the model (checkout, transfer, import), use a service.

### STI vs Polymorphic Associations

| | STI | Polymorphic |
|--|-----|------------|
| **Use when** | Subclasses share most columns | Types have unique attributes |
| **Table** | One table, `type` column | Separate tables per type |
| **Good for** | `Vehicle` -> `Car`, `Truck` | `Comment` -> on `Post`, `Photo`, `Video` |
| **Avoid when** | Many NULL columns per subtype | Types are fundamentally similar |

**Rule of thumb:** If more than 20% of columns are subtype-specific, don't use STI.

### Callbacks vs Explicit Calls

**2025 consensus: strongly favor explicit calls over callbacks.**

```ruby
# BAD: Hidden side effects in callbacks
class User < ApplicationRecord
  after_create :send_welcome_email
  after_create :create_default_settings
  after_create :notify_admin
  after_create :sync_to_crm
end

# GOOD: Explicit orchestration in service
class RegisterUser
  def call(params)
    user = User.create!(params)
    UserMailer.welcome(user).deliver_later
    CreateDefaultSettings.call(user)
    NotifyAdmin.call(user)
    SyncToCrm.call(user)
    user
  end
end
```

**When callbacks are acceptable:**
- Simple data normalization: `before_validation :strip_whitespace`
- Always-true data transformations: `before_save :downcase_email`
- Database-level consistency: `before_destroy :check_dependencies`

**Never for:**
- Sending emails
- Creating related records with business logic
- Calling external APIs
- Anything contextual (happens sometimes but not always)

### Minitest vs RSpec

Both are excellent. The 2025 community is split:
- **Minitest**: Ships with Rails, lean, fast, closer to plain Ruby
- **RSpec**: Expressive DSL, larger ecosystem, better for living documentation

Choose based on team preference. Don't switch mid-project.

---

## 9. Anti-Patterns to Avoid

### The God Model

```ruby
# BAD: Model does everything
class User < ApplicationRecord
  # 500+ lines
  # Handles auth, billing, notifications, reporting, admin...
end

# GOOD: Extract to focused collaborators
class User < ApplicationRecord
  # 50 lines: validations, associations, simple scopes
end
# + UserRegistrationService, BillingService, NotificationPreferences, etc.
```

### The Service Graveyard

```ruby
# BAD: Service for every trivial operation
class UpdateUserName
  def call(user, name)
    user.update!(name: name)
  end
end

# GOOD: Just use the model
user.update!(name: params[:name])
```

Don't create services for simple CRUD. The bar for extraction is real complexity.

### Callback Spaghetti

```ruby
# BAD: Cascading callbacks across models
class Order < ApplicationRecord
  after_create :update_inventory    # triggers Inventory callbacks
  after_create :charge_payment      # triggers Payment callbacks
  after_create :send_notifications  # triggers Notification callbacks
  # Each of those triggers more callbacks...
end

# Result: unpredictable execution order, impossible to test in isolation
```

### N+1 Ignorance

```ruby
# BAD: Looks simple, triggers 101 queries
@posts = Post.limit(100)
@posts.each { |p| p.author.name }

# GOOD: 2 queries total
@posts = Post.includes(:author).limit(100)
```

### Premature Abstraction

```ruby
# BAD: Abstract base class for two services
class BaseService
  def initialize(params); end
  def validate!; end
  def execute; end
  def notify; end
  def call
    validate!
    result = execute
    notify
    result
  end
end

# GOOD: Just write the two services independently
# Extract a base class only when you have 5+ services with identical structure
```

### Over-Testing

```ruby
# BAD: Testing Rails framework behavior
it "has a name column" do
  expect(User.column_names).to include("name")
end

# BAD: Testing implementation details
it "calls the private method" do
  expect(service).to receive(:validate_params).and_call_original
  service.call
end

# GOOD: Testing behavior
it "rejects orders with negative totals" do
  order = build(:order, total: -1)
  expect(order).not_to be_valid
end
```

---

## Sources

- [The Ruby on Rails Doctrine](https://rubyonrails.org/doctrine)
- [Rails World 2025: A Call for Radical Simplicity](https://medium.com/@abhinavcherukuru/rails-world-2025-a-call-for-radical-simplicity-and-ownership-in-web-development-41a19ec3bbdf)
- [DHH's Rails World 2025 Keynote: We're All CRUD Monkeys](https://prateekcodes.com/dhh-rails-world-2025-keynote-crud-monkeys/)
- [Rails Best Practices 2025: Why Boring Works](https://medium.com/@alessandro_89911/rails-best-practices-2025-for-us-why-boring-works-14028f8ef11b)
- [Rails Testing Best Practices 2025](https://jetthoughts.com/blog/rails-testing-best-practices-complete-guide-2025/)
- [Ruby on Rails 8 Modern Architecture Overview](https://medium.com/@ronakabhattrz/ruby-on-rails-8-modern-architecture-overview-2025-592a1f4d146c)
- [Layered Architecture in Ruby on Rails](https://patrick204nqh.github.io/tech/rails/architecture/layered-architecture-in-ruby-on-rails-a-deep-dive/)
- [Concerns vs Service Objects](https://www.derekneighbors.com/2025/01/13/concerns-vs-service-objects)
- [SOLID Principles in Rails](https://danielpaul.me/blog/solid-principles-rails)
- [Rails 8 Solid Trifecta](https://devot.team/blog/rails-solid-trifecta)
- [OWASP Ruby on Rails Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Ruby_on_Rails_Cheat_Sheet.html)
- [Rails Security Measures Guide](https://railsdrop.com/2025/05/11/a-complete-guide-to-ruby-on-rails-security-measures/)
- [ActiveRecord Anti-Patterns: Callbacks](https://rubywizards.com/activerecord-anti-patterns-which-you-should-avoid-part-2-callbacks)
- [Skinny Controllers, Skinny Models](https://thoughtbot.com/blog/skinny-controllers-skinny-models)
- [The Testing Pyramid for Rails](https://semaphore.io/blog/test-pyramid-ruby-on-rails)
- [ViewComponent Documentation](https://viewcomponent.org/)
