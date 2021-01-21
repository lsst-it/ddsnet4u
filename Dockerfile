FROM ruby:2.7.2-alpine3.13

ARG CONF_FILE='/usr/local/etc/ddsnet4u.yaml'

RUN apk add --no-cache --upgrade bash iproute2 musl-dev ruby-dev gcc make

WORKDIR /usr/local/ddsnet4u
COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1
RUN bundle config set without 'development'
RUN bundle install

COPY ddsnet4u.rb ./
COPY ddsnet4u.yaml "${CONF_FILE}"

CMD ["/usr/local/ddsnet4u/ddsnet4u.rb"]
