# syntax = docker/dockerfile:1

# Make sure it matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=4
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl postgresql-client util-linux passwd tar && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives && \
    groupadd --system --gid 1000 rails && \
    useradd --system --uid 1000 --gid 1000 --create-home rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages need to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git pkg-config libffi-dev libyaml-dev libclang-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install Rust toolchain (Debian cargo is too old for html-to-markdown's deps)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

# Install application gems
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application code
COPY . .

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Image metadata
ARG OCI_DESCRIPTION
LABEL org.opencontainers.image.description="${OCI_DESCRIPTION}"
ARG OCI_SOURCE=https://github.com/dilolabs/nosia
LABEL org.opencontainers.image.source="${OCI_SOURCE}"
LABEL org.opencontainers.image.licenses="MIT"

# Keep shipped code and dependencies outside the runtime user's write access.
COPY --from=build --chown=root:root /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=root:root /rails /rails
RUN mkdir -p /rails/tmp/pids /rails/log /rails/storage && \
    chown -R rails:rails /rails/tmp /rails/log /rails/storage

# Set version and revision
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION
ARG GIT_REVISION
ENV GIT_REVISION=$GIT_REVISION

# Advertise only a versioned native contract. Source/schema are verified by the release tooling.
ARG NATIVE_SCHEMA_VERSION
LABEL org.opencontainers.image.revision="${GIT_REVISION}" \
      io.nosia.native.protocol="1" \
      io.nosia.native.schema="${NATIVE_SCHEMA_VERSION}"
RUN chmod 755 bin/nosia-entrypoint bin/nosia-native-boot bin/nosia-native-capabilities
USER rails:rails
ENTRYPOINT ["/rails/bin/nosia-entrypoint"]

# Caddy forwards HTTP to Puma on the internal application port.
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
  CMD curl --fail --silent --max-time 4 --header "X-Forwarded-Proto: https" http://127.0.0.1:${PORT:-3000}/up || exit 1

# Start the server by default, this can be overwritten at runtime
CMD ["bin/boot"]
