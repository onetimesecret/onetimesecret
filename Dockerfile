FROM ruby:2.2.3

RUN groupadd -r ots && useradd -r -m -g ots ots
RUN apt-get update
RUN apt-get install -y build-essential libyaml-dev libevent-dev zlib1g zlib1g-dev openssl libssl-dev libxml2 git

RUN gem install bundler
RUN mkdir -p /etc/onetime && chown ots /etc/onetime
ADD . /home/ots/onetime

RUN cd /home/ots/onetime && bundle install --frozen --deployment --without=dev

RUN mkdir -p /var/log/onetime /var/run/onetime /var/lib/onetime
RUN chown ots /var/log/onetime /var/run/onetime /var/lib/onetime
RUN cp -r /home/ots/onetime/etc/* /etc/onetime

RUN echo $ots_domain | xargs -I domurl sed -ir 's/:domain:/:domain: domurl/g' /etc/onetime/config
RUN echo $ots_host | xargs -I hosturl sed -ir 's/:domain:/:domain: hosturl/g' /etc/onetime/config

EXPOSE 7143

ENTRYPOINT dd if=/dev/urandom bs=40 count=1 | openssl sha1 | grep stdin | awk '{print $2}' | xargs -I key sed -ir 's/:secret:/:secret: key/g' /etc/onetime/config && cd /home/ots/onetime/ && bundle exec thin -e dev -R config.ru -p 7143 start
