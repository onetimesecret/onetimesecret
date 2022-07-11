# ONE-TIME SECRET - v0.11-RC2 (2022-07-02)

*Keep sensitive info out of your email & chat logs.*

## What is a One-Time Secret? ##

A one-time secret is a link that can be viewed only once. A single-use URL.

<a class="msg" href="https://onetimesecret.com/">Give it a try!</a>

## Why would I want to use it? ##

When you send people sensitive info like passwords and private links via email or chat, there are copies of that information stored in many places. If you use a one-time link instead, the information persists for a single viewing which means it can't be read by someone else later. This allows you to send sensitive information in a safe way knowing it's seen by one person only. Think of it like a self-destructing message.

## Dependencies

* Any recent Linux (we use Debian, Ubuntu, and CentOS)
* Ruby 2.2+, 1.9.1+
* Redis 2.6+

## Install Dependencies

*Debian*

```bash
  sudo apt-get update
  sudo apt-get install build-essential
  sudo apt-get install ntp libyaml-dev libevent-dev zlib1g zlib1g-dev openssl libssl-dev libxml2 libreadline-gplv2-dev
  sudo apt-get install ruby redis ruby-bundler ruby-dev
  mkdir ~/sources
```

*CENTOS*

```bash
  sudo yum install gcc gcc-c++ make libtool git ntp
  sudo yum install openssl-devel readline-devel libevent-devel libyaml-devel zlib-devel
  mkdir ~/sources
```

## Install One-Time Secret

```bash
  sudo adduser ots
  sudo mkdir /etc/onetime
  sudo chown ots /etc/onetime

  sudo su - ots
  git clone https://github.com/onetimesecret/onetimesecret.git
  cd onetimesecret
  bundle install --frozen
  bin/ots init
  sudo mkdir /var/log/onetime /var/run/onetime /var/lib/onetime
  sudo chown ots /var/log/onetime /var/run/onetime /var/lib/onetime
  mkdir /etc/onetime
  cp -rp etc/* /etc/onetime/
  chown -R ots /etc/onetime /var/lib/onetime
  chmod -R o-rwx /etc/onetime /var/lib/onetime
```

### About git cloning

The instructions above suggest cloning via the `https` URI. You can also clone using the SSH URI if you have a github account (which is generally more convenient, but specific to github).

**With a github account**
```bash
  ssh -T git@github.com
  Hi delano! You've successfully authenticated, but GitHub does not provide shell access.
```

**Without a github account**
```bash
  ssh -T git@github.com
  Warning: Permanently added the RSA host key for IP address '0.0.0.0/0' to the list of known hosts.
  git@github.com: Permission denied (publickey).
```

*NOTE: you can also use the etc directory from here instead of copying it to the system. Just be sure to secure the permissions on it*

```bash
  chown -R ots ./etc
  chmod -R o-rwx ./etc
```

### Update the configuration

1. `/etc/onetime/config`
  * Update your secret key
    * Store it in your password manager because it's included in the secret encryption
  * Add or remove locales
  * Update the SMTP or SendGrid credentials
  * Update the from address
    * it's used for all sent emails
  * Update the the limits at the bottom of the file
    * These numbers refer to the number of times each action can occur for unauthenticated users.
    * If you would like to increase the limits for authenticated users too, see (lib/onetime.rb](https://github.com/onetimesecret/onetimesecret/blob/main/lib/onetime.rb#L261-L279)
1. `/etc/onetime/redis.conf`
  * The host, port, and password need to match
1. `/etc/onetime/locale/*`
  * Optionally you can customize the text used throughout the site and emails
  * You can also edit the `:broadcast` string to display a brief message at the top of every page

### Running

There are many way to run the webapp, just like any Rack-based app. The default web server we use is [thin](https://github.com/macournoyer/thin).

**To run locally:**

```bash
  bundle exec thin -e dev -R config.ru -p 7143 start
```

**To run on a server:**

```bash
  bundle exec thin -d -S /var/run/thin/thin.sock -l /var/log/thin/thin.log -P /var/run/thin/thin.pid -e prod -s 2 restart
```

**To run with docker:**

```bash
  docker compose up
  open http://localhost:3000/
```

## Generating a global secret

We include a global secret in the encryption key so it needs to be long and secure. One approach for generating a secret:

```bash
  dd if=/dev/urandom bs=20 count=1 | openssl sha256
```
