# To use this image, you need a Redis database with persistence enabled.
# You can start one with Docker using i.e.:
#
# $ docker run -p 6379:6379 -d redis
#
# Then start this image, specifying the URL of the redis database:
#
# $ docker run -p 3000:3000 -d \
#     -e ONETIMESECRET_REDIS_URL="redis://172.17.0.1:6379/0" \
#     onetimesecret
#
# It will be accessible on http://localhost:3000.
#
# Production deployment
# ---------------------
#
# When deploying to production, you should protect your Redis instance
# with authentication or Redis networks. You should also enable
# persistence and save the data somewhere, to make sure it doesn't get
# lost when the server restarts.
#
# You should also change the secret to something else, and specify the
# domain it will be deployed on.
# For instance, if OTS will be accessible from https://example.com:
#
# $ docker run -p 3000:3000 -d \
#     -e ONETIMESECRET_REDIS_URL="redis://user:password@host:port/0" \
#     -e ONETIMESECRET_SSL=true -e ONETIMESECRET_HOST=example.com \
#     -e ONETIMESECRET_SECRET="<put your own secret here>" \
#     onetimesecret

FROM ruby:2.3

WORKDIR /usr/src/app
COPY Gemfile Gemfile.lock ./
RUN bundle install --frozen --deployment --without=dev
COPY . .
CMD ["bundle", "exec", "thin", "-R", "config.ru", "start"]

EXPOSE 3000
ENV RACK_ENV prod
ENV ONETIMESECRET_SSL=false \
    ONETIMESECRET_HOST=localhost:3000 \
    ONETIMESECRET_SECRET=CHANGEME \
    ONETIMESECRET_REDIS_URL= \
    ONETIMESECRET_COLONEL=
