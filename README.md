# Onetime Secret — Secure One-Time Message Sharing

_Keep passwords and other sensitive information out of your chat logs and emails._

> [!NOTE]
> Development happens on GitLab: <https://gitlab.com/onetimesecret/onetimesecret>.
> Open issues and merge requests there. The GitHub repository is a read-only
> mirror, and the Docker Hub and GHCR images are still built from it.

A **one-time secret** is a link that can be viewed only once — a single-use URL.
When you share sensitive info like a password over email or chat, copies linger
in many places. Onetime links self-destruct after viewing, so only the intended
recipient ever sees the contents.

**[Try it live at OnetimeSecret.com →](https://onetimesecret.com/)**

## Quick Start (Docker)

```bash
(
  set -e
  umask 077
  workdir=$(pwd -P)
  current_uid=$(id -u)
  path=$workdir
  while :; do
    path_meta=$(stat -c '%u %a' "$path" 2>/dev/null || stat -f '%u %p' "$path")
    read -r path_owner path_mode <<< "$path_meta"
    case $path_owner in ''|*[!0-9]*) printf 'Cannot verify directory owner.\n' >&2; exit 1 ;; esac
    case $path_mode in ''|*[!0-7]*) printf 'Cannot verify directory mode.\n' >&2; exit 1 ;; esac
    unsafe_path=false
    if [ "$(uname -s)" = Darwin ]; then
      acl_info=$(LC_ALL=C ls -lde "$path") || exit 1
      [ -n "$acl_info" ] || unsafe_path=true
      first_line=true
      while IFS= read -r acl_line; do
        if $first_line; then
          first_line=false
          case $acl_line in d?????????*) ;; *) unsafe_path=true ;; esac
          continue # the first line includes the pathname, not an ACL entry
        fi
        if [[ $acl_line =~ ^[[:space:]]*[0-9]+:[[:space:]]+ ]]; then
          case $acl_line in
            *' allow '*) unsafe_path=true ;;
            *' deny '*) ;;
            *) unsafe_path=true ;;
          esac
        else
          unsafe_path=true
        fi
      done <<< "$acl_info"
    fi
    if [ "$path" = "$workdir" ]; then
      if [ "$path_owner" -ne "$current_uid" ] || [ $((8#$path_mode & 022)) -ne 0 ]; then
        unsafe_path=true
      fi
    elif { [ "$path_owner" -ne 0 ] && [ "$path_owner" -ne "$current_uid" ]; } ||
         { [ $((8#$path_mode & 022)) -ne 0 ] && [ $((8#$path_mode & 01000)) -eq 0 ]; }; then
      unsafe_path=true
    fi
    if $unsafe_path; then
      printf 'Run this quick start in a private directory under protected parents.\n' >&2
      exit 1
    fi
    [ "$path" = / ] && break
    path=${path%/*}
    [ -n "$path" ] || path=/
  done
  ensure_key_file() {
    key_file=$1
    if [ -L "$key_file" ]; then
      printf 'Refusing linked key file: %s\n' "$key_file" >&2
      return 1
    fi
    if [ -e "$key_file" ]; then
      if [ ! -f "$key_file" ] || [ ! -s "$key_file" ]; then
        printf 'Refusing invalid key file: %s\n' "$key_file" >&2
        return 1
      fi
      chmod 600 "$key_file"
    else
      key=$(openssl rand -hex 32)
      private_dir=$(mktemp -d .ots-key.XXXXXXXX)
      if chmod 700 "$private_dir" &&
         printf '%s\n' "$key" > "$private_dir/key" &&
         chmod 600 "$private_dir/key" &&
         ln -n "$private_dir/key" "$key_file"; then
        rm -rf "$private_dir"
      else
        rm -rf "$private_dir"
        return 1
      fi
    fi
  }

  # 1. Create private credentials; preserve existing key files
  ensure_key_file .ots_redis_password
  ensure_key_file .ots_secret # back up this persistent key safely

  # 2. Start Redis on a private Docker network, password-protected and with
  #    no host port — the app reaches it by container name
  docker network create onetime
  docker run -d --name onetime-redis --network onetime redis:trixie \
    redis-server --requirepass "$(cat .ots_redis_password)"

  # 3. Run Onetime Secret for local evaluation; use a TLS proxy for remote access
  docker run -p 127.0.0.1:3000:3000 -d \
    --name onetimesecret \
    --network onetime \
    -e REDIS_URL="redis://:$(cat .ots_redis_password)@onetime-redis:6379/0" \
    -e SECRET="$(cat .ots_secret)" \
    -e HOST=localhost:3000 \
    -e SSL=false \
    onetimesecret/onetimesecret:v0.26.14
)
```

Open <http://localhost:3000>, then create an admin ("colonel") account — it
prints a generated password and is verified immediately:

```bash
docker exec onetimesecret bin/ots customers create me@example.com --role colonel
```

> [!IMPORTANT]
> **Losing your `SECRET` key is not recoverable**. It makes existing
> secrets unreadable among other things, so back it up.

## Going further

- **Self-hosting** — reverse proxy, full authentication (PostgreSQL + RabbitMQ, MFA, WebAuthn), and production hardening: [Self-Hosting Guide](https://docs.onetimesecret.com/en/self-hosting/)
- **Docker Compose** — simple and full stacks: [docker/README.md](./docker/README.md)
- **Configuration** — [.env.reference](./.env.reference) and [config defaults](./etc/defaults/config.defaults.yaml)
- **Contributing** — from clone to a green test suite in two commands, plus [test accounts & API tokens](./docs/development/test-accounts.md): [CONTRIBUTING.md](./CONTRIBUTING.md)

## Community & Support

- **Get help** — [Documentation](https://docs.onetimesecret.com) · [Report an issue](https://github.com/onetimesecret/onetimesecret/issues) · [Support](./SUPPORT.md)
- **Project** — [Latest Release](https://github.com/onetimesecret/onetimesecret/releases/latest) · [Docker Hub](https://hub.docker.com/r/onetimesecret/onetimesecret) · [Build Status](https://github.com/onetimesecret/onetimesecret/actions)
- **Policies** — [Security](./SECURITY.md) · [Code of Conduct](./CODE_OF_CONDUCT.md)
- **See also** — [Similar services & alternatives](./docs/similar-services.md)

## AI Development Assistance

Onetime Secret was developed with help from AI tools for architecture design,
code generation, and documentation. As project maintainers, we remain responsible
for all design decisions and the final code, and believe in being transparent
about the tools involved.

## License

MIT — see [LICENSE.txt](./LICENSE.txt).
