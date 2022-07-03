# Onetime v2 - Initial Setup - 2022-06-28


## Initial setup

Note: You'll have the least bad time if _you use the "root" credentials_. For RDS, it's the user that was added when the database was created e.g. `postgres`.

1. Checkout develop
1. Copy `run/.env.empty` to `run/.env`
1. Update the database credentials
1. Run SQL to prepare database

   - Take a look at `share/sql/01_create_users.sql` to see the usernames and default password.
     - In the header doc is the SQL needed to change the passwords to a secure value.
     - For AWS credentials, you can put them all into a single 1Password item (e.g. multiple password fields)
   - `psql -U onetime -W -h 0.0.0.0 postgres < ./share/sql/01_create_users.sql`
   - `psql -U onetime -W -h 0.0.0.0 postgres < ./share/sql/02_create_databases.sql`
   - The `03_grants.sql` needs to run in every new database.
     - `psql -U onetime -W -h 0.0.0.0 responses < ./share/sql/03_grants.sql`
     - `psql -U onetime -W -h 0.0.0.0 activity_results < ./share/sql/03_grants.sql`
     - `psql -U onetime -W -h 0.0.0.0 filterable_responses < ./share/sql/03_grants.sql`
   - And for onetime.
     - `psql -U onetime -W -h 0.0.0.0 onetime < ./share/sql/03_grants.sql`

1. Copy run/config/docker-compose.yml to run/docker-compose.yml
1. Try to build onetime: `sudo docker-compose build onetime`

   - The container names are listed in the docker compose YAML file: `onetime`,  and `onetime`. They can all see each other so you in theory could `ssh
   
1. There's a non-zero percent chance something will need to be modified.
1. Try running in attached mode: `sudo docker-compose up onetime`
1. Try running in daemon mode: `sudo docker-compose up -d onetime`

## Deploying to production

Note: We shouldn't rely on pushing git directly to production machine. I present it as an example for the 1-click deployment.

_First make sure you can SSH into the machine._

```bash

  # Do this once
  $ git remote add onetime admin@onetime-web:/home/onetime/onetime-onetime-v2

  # If you need to change the URL.
  # Or just edit .git/config
  $ git remote set-url onetime admin@onetime-web:/home/onetime/onetime-onetime-v2

  # Same as pushing to github, just onetime instead of origin
  $ git push onetime develop

```

### Restart automatically

[Git commit hooks](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks) are a simple and effective way of getting things done with a small amount of effort. They run only locally -- it's a normal script and git doesn't even try to do anything fancy. IOW, do this on the EC2 instance where it's meant to run.

```bash

  # Edit the post-update hook with something like the following
  $ vi .git/hooks/post-receive.sample
  $ mv .git/hooks/post-receive.sample .git/hooks/post-receive

  # See an example script inside the toggle below.

```

<details>

<summary>Example for .git/hooks/post-receive script</summary>

```bash
#!/bin/bash

#
# GIT HOOK - ON POST RECEIVE (2022-06-28)
#
# A demonstration of a script that gets called after
# receiving a push. This is not meant for production use.
#

set -e

_date=`date --iso-8601=ns`
_starting_point=`pwd`
_args=${@}

_dc_home="${ONETIME_HOME}/run"
_dc_container=onetime

function main() {
  ilog  "[${_date}] ${_starting_point}"
  ilog "${_args:-[no args]}"

  # Bust out of .git
  cd ${_dc_home:?Nowhere to go}

  ilog `pwd`
  source .env

  echo "This could be the output from a docker-compose command"

  # e.g.
  # sudo docker-compose ps && sudo docker-compose restart "${_dc_container:?No container name}"

}

function ilog() {
  if (( ${DEBUG} )); then
    echo "[D] ${@}"
  else
    logger -t onetime $@
  fi
}


main $@

```

</details>

### Helpful Commands

```bash
  $ sudo docker-compose stop onetime
  $ sudo docker-compose stop

  $ sudo docker-compose restart onetime

  $ sudo docker-compose ps
  $ sudo docker-compose config
  $ sudo docker-compose config onetime
  $ sudo docker-compose logs
  $ sudo docker-compose logs onetime

  $ sudo docker inspect onetime
  $ sudo docker ps
  $ sudo docker stats
  $ sudo docker image ls
  $ sudo docker container ls
  $ sudo docker volumes ls
```

### SSH Config

Add this to you `~/.ssh/config` file

```ssh-config
Host onetime-web
  HostName                  192.168.82.55
  IdentityFile              ~/.ssh/CHANGEME
  User                      admin
  UseKeychain               yes
  AddKeysToAgent            yes
  ForwardAgent              yes
```

```bash

  $ ssh onetime-web

  admin@onetime-web:~/

```
