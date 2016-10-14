FROM ruby:2.3.1

#
# Make sure to edit etc/config in this repo prior to building this container.
#

RUN \
  apt-get update -qq && \
  apt-get install -y \
  build-essential \
  ntp \
  libevent-dev \
  zlib1g \
  zlib1g-dev \
  openssl \
  libreadline-gplv2-dev

ENV APP_HOME /app
RUN mkdir $APP_HOME
ADD . $APP_HOME
WORKDIR $APP_HOME

RUN bundle install --deployment --without dev

ENV PORT=7143
EXPOSE $PORT
CMD bundle exec thin -R config.ru -p $PORT -a 0.0.0.0 start
