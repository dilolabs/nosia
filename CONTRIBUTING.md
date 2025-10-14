# Contributing to Nosia

Thank you for your interest in contributing to Nosia! We welcome contributions from the community and are grateful for your support.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [How to Contribute](#how-to-contribute)
- [Pull Request Process](#pull-request-process)
- [Development Guidelines](#development-guidelines)
- [Testing](#testing)
- [Documentation](#documentation)
- [Getting Help](#getting-help)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Getting Started

### Prerequisites

Before you begin, ensure you have the following installed:

- **Docker** and **Docker Compose** (for containerized development)
- **Ruby** 3.3+ (for local development)
- **PostgreSQL** 15+ with pgvector extension
- **Git** for version control

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone git@github.com/USERNAME/nosia.git
   cd nosia
   ```
3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/dilolabs/nosia.git
   ```

## Development Setup

### Option 1: Docker Development (Recommended)

1. Copy the environment file:
   ```bash
   cp .env.example .env
   ```

2. Generate a secret key:
   ```bash
   docker compose run web bin/rails secret
   # Copy the output and add to .env as SECRET_KEY_BASE
   ```

3. Start the development environment:
   ```bash
   docker compose up -d
   ```

4. Create and migrate the database:
   ```bash
   docker compose exec web bin/rails db:create db:migrate
   ```

5. Access the application at `https://nosia.localhost`

### Option 2: Local Development

1. Install Ruby dependencies:
   ```bash
   bundle install
   ```

2. Copy and configure environment:
   ```bash
   cp .env.example .env
   # Edit .env with your local configuration
   ```

3. Setup the project:
   ```bash
   bin/setup
   ```

5. Start the development server:
   ```bash
   bin/dev
   ```

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check the [issue tracker](https://github.com/nosia-ai/nosia/issues) to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce** the issue
- **Expected behavior** vs. actual behavior
- **Environment details** (OS, Docker version, Nosia version)
- **Relevant logs** (remove sensitive information)
- **Screenshots** if applicable

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, include:

- **Clear title and description** of the enhancement
- **Use case** explaining why this would be useful
- **Possible implementation** approach (if you have ideas)
- **Examples** from other projects (if applicable)

### Your First Code Contribution

Unsure where to begin? Look for issues labeled:

- `good first issue` - Good for newcomers
- `help wanted` - Issues that need assistance
- `documentation` - Documentation improvements

### Contributing Code

1. **Create a branch** for your work:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-number-description
   ```

2. **Make your changes** following our [development guidelines](#development-guidelines)

3. **Test your changes** thoroughly

4. **Commit your changes** with clear, descriptive messages:
   ```bash
   git commit -m "Add feature: description of what you added"
   # or
   git commit -m "Fix #123: description of the fix"
   ```

5. **Keep your fork updated**:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

6. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Open a Pull Request** on GitHub

## Pull Request Process

1. **Update documentation** if you've changed APIs or added features

2. **Ensure tests pass**:
   ```bash
   docker compose exec web bin/rails test
   ```

3. **Follow the Ruby style guide** - Run RuboCop:
   ```bash
   docker compose exec web bundle exec rubocop
   ```

4. **Update CHANGELOG.md** if applicable (for significant changes)

5. **Fill out the pull request template** completely

6. **Link related issues** using keywords like "Fixes #123" or "Relates to #456"

7. **Be responsive** to review feedback and questions

### Pull Request Review Process

- Maintainers will review your PR and may request changes
- Address feedback by pushing new commits to your branch
- Once approved, a maintainer will merge your PR
- After merging, you can safely delete your branch

## Development Guidelines

### Code Style

- **Ruby**: Follow the [Ruby Style Guide](https://rubystyle.guide/)
- Run RuboCop before committing:
  ```bash
  bundle exec rubocop
  # Auto-fix issues when possible
  bundle exec rubocop -a
  ```

### Commit Messages

Write clear, concise commit messages:

- Use the present tense ("Add feature" not "Added feature")
- Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters
- Reference issues and pull requests when applicable
- For complex changes, include a detailed description after the first line

Examples:
```
Add RAG context retrieval for chat completions

Implements semantic search to retrieve relevant document chunks
before generating chat responses. Includes configurable fetch_k
parameter to control number of chunks retrieved.

Fixes #123
```

### Code Organization

- Keep methods small and focused on a single responsibility
- Use meaningful variable and method names
- Add comments for complex logic, but prefer self-documenting code
- Follow Rails conventions for file and directory structure
- Use concerns for shared behavior across models or controllers

### Database Migrations

- Write reversible migrations when possible
- Test migrations both up and down
- Include clear comments for complex migrations
- Never edit existing migrations that have been merged to main

## Testing

### Running Tests

Run the full test suite:
```bash
docker compose exec web bin/rails test
```

Run specific test files:
```bash
docker compose exec web bin/rails test test/models/document_test.rb
```

Run tests with coverage:
```bash
docker compose exec web bin/rails test COVERAGE=true
```

### Writing Tests

- Write tests for new features and bug fixes
- Follow existing test patterns and conventions
- Use fixtures or factories for test data
- Mock external API calls
- Test edge cases and error conditions
- Aim for meaningful test coverage, not just high percentages

### Test Organization

- Unit tests in `test/models/`, `test/helpers/`, etc.
- Integration tests in `test/integration/`
- System tests in `test/system/`
- Test fixtures in `test/fixtures/`

## Documentation

### Types of Documentation

1. **Code Documentation**
   - Add documentation for public methods
   - Include examples for complex APIs
   - Document parameters, return values, and exceptions

2. **README Updates**
   - Update README.md for new features or configuration changes
   - Keep installation instructions current
   - Add examples for new functionality

3. **Architecture Documentation**
   - Update [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for architectural changes
   - Add diagrams when helpful
   - Document design decisions and trade-offs

### Documentation Style

- Write in clear, simple language
- Use active voice
- Include code examples
- Test all commands and code snippets
- Keep documentation up to date with code changes

## Getting Help

### Questions and Discussions

- **GitHub Discussions**: For general questions and discussions
- **GitHub Issues**: For bug reports and feature requests
- **Documentation**: Check [docs/README.md](docs/README.md) first

### Communication Guidelines

- Be respectful and patient
- Search for existing discussions before posting
- Provide context and details in your questions
- Follow up and share solutions you find

## Recognition

Contributors who have their pull requests merged will be:

- Listed in our contributors list
- Credited in release notes for significant contributions
- Invited to join our community of maintainers for sustained contributions

## License

By contributing to Nosia, you agree that your contributions will be licensed under the same license as the project. See [LICENSE](LICENSE) for details.

---

Thank you for contributing to Nosia! Your efforts help make this project better for everyone.
