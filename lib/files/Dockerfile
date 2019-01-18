# syntax=docker/dockerfile:experimental
FROM ruby:2.5.1-slim

# Oracle Client
COPY ./oracle /oracle
WORKDIR /oracle

# Build tools, nokogiri, capybara-webkit, JS runtime (yarn)
# debian wants to use cmtest inplace of yarn, so remove that and install yarn before node
RUN apt-get update -qq \
&&  apt-get install -y build-essential apt-utils apt-transport-https  \
&&  curl -sL https://deb.nodesource.com/setup_10.x | bash -           \
&&  curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
&&  echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
&&  apt-get update -qq                                                \
&&  apt-get install --no-install-recommends -y                        \
      libxml2-dev libxslt1-dev libqtwebkit4 libqt4-dev                \
      xvfb yarn nodejs vim                                            \
&&  rm -rf /var/lib/apt/lists/*

# Create rails user
RUN  useradd -m -u 1000 -U rails

ENV APP_HOME /app
WORKDIR $APP_HOME
COPY Gemfile* $APP_HOME
COPY vendor $APP_HOME/vendor
ARG RAILS_MASTER_KEY
RUN --mount=type=ssh bundle package --all

RUN mkdir -p /volumes/public && chown -R rails /volumes/public

ENV APP_HOME /app
WORKDIR $APP_HOME

# need copy the app over, before chown-ing it, otherwise use won't have permission to precompile assets
COPY . $APP_HOME
RUN chown -R rails $APP_HOME
USER rails

HEALTHCHECK CMD curl -f localhost:3000/healthcheck

STOPSIGNAL SIGINT
ENTRYPOINT ["bundle", "exec"]

RUN ["rails", "assets:precompile"]
CMD ["rails", "start"]
