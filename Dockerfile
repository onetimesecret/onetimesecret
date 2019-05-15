FROM debian:stretch

RUN apt-get update
RUN apt-get install -y build-essential ruby ruby-dev redis-server procps
RUN apt-get install -y libyaml-dev libevent-dev zlib1g zlib1g-dev openssl \
					   libssl-dev libxml2 libreadline-gplv2-dev
RUN gem install bundler

# Copy source, you need to setup etc/redis.conf & etc/config before building image
COPY . /home/ots/onetimesecret

# Add user ots, set perms and copy conf files
RUN useradd ots -s /bin/bash -d /home/ots -m
RUN mkdir /etc/onetime && chown ots /etc/onetime
RUN mkdir /var/log/onetime /var/run/onetime /var/lib/onetime
RUN chown ots /var/log/onetime /var/run/onetime /var/lib/onetime /home/ots -R
RUN cp -R /home/ots/onetimesecret/etc/* /etc/onetime/

# Install app with ots user
USER ots
WORKDIR /home/ots/onetimesecret
RUN bundle install --frozen --deployment --without=dev
RUN bin/ots init

# clean packages 
USER root
RUN apt-get purge -y build-essential && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Run app with ots user
USER ots
WORKDIR /home/ots/onetimesecret
CMD ["sh", "/home/ots/onetimesecret/bin/run.sh"]
