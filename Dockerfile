FROM ruby:3.0.0

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./
RUN gem install bundler
RUN bundle install

COPY . .

RUN bundle exec rake assets:precompile

ENV LANG C.UTF-8
ENV PORT 5000
ENV RACK_ENV production

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]