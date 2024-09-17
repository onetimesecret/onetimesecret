# Onetime Secret - v0.17

*Keep passwords and other sensitive information out of your inboxes and chat logs.*

### Latest releases

* **Ruby 3+ (recommended): [latest](https://github.com/onetimesecret/onetimesecret/releases/latest)**
* Ruby 2.7, 2.6: [v0.12.1](https://github.com/onetimesecret/onetimesecret/releases/tag/v0.12.1)

---


## What is a Onetime Secret?

A onetime secret is a link that can be viewed only once. A single-use URL.

Try it out on <a class="msg" href="https://onetimesecret.com/">OnetimeSecret.com</a>!


### Why would I want to use it?

When you send people sensitive info like passwords and private links via email or chat, there are copies of that information stored in many places. If you use a Onetime link instead, the information persists for a single viewing which means it can't be read by someone else later. This allows you to send sensitive information in a safe way knowing it's seen by one person only. Think of it like a self-destructing message.


## Installation

### System Requirements

* Any recent linux disto (we use debian) or *BSD
* System dependencies:
  * Ruby 3.3, 3.2, 3.1, 3.0, 2.7.8
  * Redis server 5+
* Minimum specs:
  * 2 core CPU (or equivalent)
  * 1GB memory
  * 4GB disk

For front-end development, you'll also need:
* Node.js 18+
* pnpm 7.0.0+


### Docker

Running from a container is the easiest way to get started. We provide a Dockerfile that you can use to build your own image, or you can use one of the pre-built images from our container repositories.


```bash
  # Install from the GitHub Container Registry
  $ docker pull ghcr.io/onetimesecret/onetimesecret:latest

  # OR, install from Docker Hub

  $ docker pull onetimesecret/onetimesecret:latest

  # Start redis container
  $ docker run -p 6379:6379 -d redis:bookworm

  # Set essential environment variables
  HOST=localhost:3000
  SSL=false
  COLONEL=admin@example.com
  REDIS_URL=redis://host.docker.internal:6379/0
  RACK_ENV=production

  # Create and run a container named `onetimesecret`
  $ docker run -p 3000:3000 -d --name onetimesecret \
      -e REDIS_URL=$REDIS_URL \
      -e COLONEL=$COLONEL \
      -e HOST=$HOST \
      -e SSL=$SSL \
      -e RACK_ENV=$RACK_ENV \
      onetimesecret/onetimesecret:latest
```

#### Building image locally

```bash
  $ docker build -t onetimesecret .
  $ docker run -p 3000:3000 -d --name onetimesecret \
      -e REDIS_URL=$REDIS_URL \
      -e COLONEL=$COLONEL \
      -e HOST=$HOST \
      -e SSL=$SSL \
      -e RACK_ENV=$RACK_ENV \
      onetimesecret
```

#### Optional Bundle Install

By default, the `bundle install` command is not run when starting the container. If you want it to run at startup (e.g., to re-install new dependencies added to the Gemfile without rebuilding the image), you can set the `BUNDLE_INSTALL` environment variable to `true`. Here's how you can do this:

```bash
$ docker run -p 3000:3000 -d --name onetimesecret \
    -e BUNDLE_INSTALL=true \
    -e REDIS_URL=$REDIS_URL \
    -e COLONEL=$COLONEL \
    -e HOST=$HOST \
    -e SSL=$SSL \
    -e RACK_ENV=$RACK_ENV \
    onetimesecret/onetimesecret:latest
```

This will cause the container to run bundle install each time it starts up. Note that this may increase the startup time of your container.


#### Multi-platform builds

Docker's buildx command is a powerful tool that allows you to create Docker images for multiple platforms simultaneously. Use buildx to build a Docker image that can run on both amd64 (standard Intel/AMD CPUs) and arm64 (ARM CPUs, like those in the Apple M1 chip) platforms.

```bash
  $ docker buildx build --platform=linux/amd64,linux/arm64 . -t onetimesecret
```

#### "The container name "/onetimesecret" is already in use"

```bash
  # If the container already exists, you can simply start it again:
  $ docker start onetimesecret

  # OR, remove the existing container
  $ docker rm onetimesecret
```

After the container has been removed, the regular `docker run` command will work again.


#### Container repositories


##### [GitHub Container Registry](https://ghcr.io/onetimesecret/onetimesecret)

```bash
  $ docker run -p 6379:6379 --name redis -d redis
  $ REDIS_URL="redis://172.17.0.2:6379/0"

  $ docker pull ghcr.io/onetimesecret/onetimesecret:latest
  $ docker run -p 3000:3000 -d --name onetimesecret \
    -e REDIS_URL=$REDIS_URL \
    ghcr.io/onetimesecret/onetimesecret:latest
```

##### [Docker Hub](https://hub.docker.com/r/onetimesecret/onetimesecret)

```bash
  $ docker run -p 6379:6379 --name redis -d redis
  $ REDIS_URL="redis://172.17.0.2:6379/0"

  $ docker pull onetimesecret/onetimesecret:latest
  $ docker run -p 3000:3000 -d --name onetimesecret \
    -e REDIS_URL=$REDIS_URL \
    onetimesecret/onetimesecret:latest
```

### Docker Compose

See the dedicated [Docker Compose repo](https://github.com/onetimesecret/docker-compose/).


### Manually

Get the code, one of:

* Download the [latest release](https://github.com/onetimesecret/onetimesecret/archive/refs/tags/latest.tar.gz)
* Clone this repo:

```bash
  $ git clone https://github.com/onetimesecret/onetimesecret.git
```

### For a fresh install

If you're installing on a fresh system, you'll need to install a few system dependencies before you can run the webapp.

#### 0. Install system dependencies

The official Ruby docs have a great guide on [installing Ruby](https://www.ruby-lang.org/en/documentation/installation/). Here's a quick guide for Debian/Ubuntu:


For Debian / Ubuntu:

```bash

  # Make sure you have the latest packages (even if you're on a fresh install)
  $ sudo apt update

  # Install the basic tools of life
  $ sudo apt install -y git curl sudo

  # Install Ruby (3) and Redis
  $ sudo apt install -y ruby-full redis-server
```

NOTE: The redis-server service should start automatically after installing it. You can check that it's up by running: `service redis-server status`. If it's not running, you can start it with `service redis-server start`.

#### 1. Now get the code via git:

```bash
  $ git clone https://github.com/onetimesecret/onetimesecret.git
```


#### 2. Copy the configuration files into place and modify as needed:

```bash
  $ cd onetimesecret

  $ cp --preserve --no-clobber ./etc/config.example ./etc/config
  $ cp --preserve --no-clobber .env.example .env
```


#### 3. Install ruby dependencies

```bash

  # We use bundler manage the rest of the ruby dependencies
  $ sudo gem install bundler

  # Install the rubygems listing inthe Gemfile
  $ bundle install
```

#### 4. Install javascript dependencies

```bash
  $ pnpm install
```

And build the assets:

```bash
  $ pnpm run build
```


#### 5. Run the webapp

```bash
  $ bundle exec thin -R config.ru -p 3000 start

  ---  ONETIME app  ----------------------------------------
  Config: /Users/d/Projects/opensource/onetimesecret/etc/config
  2024-04-10 22:39:15 -0700 Thin web server (v1.8.2 codename Ruby Razor)
  2024-04-10 22:39:15 -0700 Maximum connections set to 1024
  2024-04-10 22:39:15 -0700 Listening on 0.0.0.0:3000, CTRL+C to stop
```

See the [Ruby CI workflow](.github/workflows/ruby.yaml) for another example of the steps.

In a separate terminal window, run the Vite dev server:

```bash
  $ pnpm run dev
```

NOTE: When running the Vite server in development mode, it will automatically reload when files change. Make sure that `RACK_ENV` is either set to `development` or `development.enabled` in etc/config is false. Otherwise the ruby application will attempt to lad the JS/CSS etc from the pre-built files in `public/web/dist`.


## Debugging

To run in debug mode set `ONETIME_DEBUG=true`.

```bash
  $ ONETIME_DEBUG=true bundle exec thin -e dev start`
```

If you're having trouble cloning via SSH, you can double check your SSH config like this:

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

### Configuration

1. `./etc/config`
  * Update your secret key
    * Back up your secret key (e.g. in your password manager). If you lose it, you won't be able to decrypt any existing secrets.
  * Update the SMTP or SendGrid credentials for email sending
    * Update the from address (it's used for all sent emails)
  * Update the rate limits at the bottom of the file
    * The numbers refer to the number of times each action can occur for unauthenticated users.
  * Enable or disable the available locales.
1. `./etc/redis.conf`
  * The host, port, and password need to match
1. `/etc/onetime/locale/*`
  * Optionally you can customize the text used throughout the site and emails
  * You can also edit the `:broadcast` string to display a brief message at the top of every page

### Running your own

There are many ways to run the webapp. The default web server we use is [thin](https://github.com/macournoyer/thin). It's a Rack app so any server in the ruby ecosystem that supports Rack apps will work.

**To run locally:**

```bash
  bundle exec thin -e dev -R config.ru -p 3000 start
```

**To run on a server:**

```bash
  bundle exec thin -d -S /var/run/thin/thin.sock -l /var/log/thin/thin.log -P /var/run/thin/thin.pid -e prod -s 2 start
```

Graceful restart:
```bash
  bundle exec thin --onebyone -d -S /var/run/thin/thin.sock -l /var/log/thin/thin.log -P /var/run/thin/thin.pid -e prod -s 4 -D restart
```

## Similar Services

This section provides an overview of services similar to our project, highlighting their unique features and how they compare. These alternatives may be useful for users looking for specific functionalities or wanting to explore different options in the same domain.

**Note:** Our in-house legal counsel ([codium-pr-agent-pro bot](https://github.com/onetimesecret/onetimesecret/pull/610#issuecomment-2333317937)) suggested adding this introduction and the disclaimer at the end.

| URL | Service | Description | Distinctive Feature |
|-----|---------|-------------|---------------------|
| https://pwpush.com/ | Password Pusher | A tool that uses browser cookies to help you share passwords and other sensitive information. | Temporary, self-destructing links for password sharing |
| https://scrt.link/en | Share a Secret | A service that allows you to share sensitive information anonymously. Crucial for journalists, lawyers, politicians, whistleblowers, and oppressed individuals. | Anonymous, self-destructing message sharing |
| https://cryptgeon.com/ | Cryptgeon | A service for sharing secrets and passwords securely. | Offers a secret generator, password generator, and secret vault |
| https://www.vanish.so/ | Vanish | A service for sharing secrets and passwords securely. | Self-destructing messages with strong encryption |
| https://password.link/en | Password.link | A service for securely sending and receiving sensitive information. | Secure link creation for sensitive information sharing |
| https://sebsauvage.net/ | sebsauvage.net | A website offering various information and services. | Software to recover stolen computers |
| https://www.sharesecret.co/ | ShareSecret | A service for securely sharing passwords in Slack and email. | Secure password sharing with Slack and email integration |
| https://teampassword.com/ | TeamPassword | A password manager for teams. | Fast, easy-to-use, and secure team password management |
| https://secretshare.io/ | Secret Share | A service for sharing passwords securely. | Strong encryption for data in transit and at rest |
| https://retriever.corgea.io/ | Retriever | A service for requesting secrets securely. | Secure secret request and retrieval with encryption |
| https://winden.app/s | Winden | A service for sharing secrets and passwords securely. | Securely transfers files with end-to-end encryption |
| https://www.snote.app/ | SNote | A privacy-focused workspace with end-to-end encryption. | Secure collaboration on projects, to-dos, tasks, and shared files |
| https://www.burnafterreading.me/ | Burn After Reading | A service for sharing various types of sensitive information. | Self-destructing messages with diceware passphrase encryption |
| https://pvtnote.com/en/ | PvtNote | A service for sending private, self-destructing messages. | Clean design with self-destructing messages |
| https://k9crypt.xyz/ | K9Crypt | A secure and anonymous messaging platform. | End-to-end encryption with 2-hour message deletion |

_Summarized, fetched, and collated by [Cohere Command R+](https://cohere.com/blog/command-r-plus-microsoft-azure), formatted by [Claude 3.5 Sonnet](https://www.anthropic.com/news/claude-3-5-sonnet), and proofread by [GitHub Copilot](https://github.com/features/copilot)._

The inclusion of these services in this list does not imply endorsement. Users are encouraged to conduct their own research and due diligence before using any of the listed services, especially when handling sensitive information.


## Generating a global secret

We include a global secret in the encryption key so it needs to be long and secure. One approach for generating a secret:

```bash
  $ dd if=/dev/urandom bs=20 count=1 | openssl sha256
```
