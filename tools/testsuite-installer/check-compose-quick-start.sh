#!/usr/bin/env bash
# Functions below are exported into child shells running the README snippets.
# shellcheck disable=SC2329

set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/docker/compose"
cp .env.example docker-compose.yml "$work/"
cp docker/compose/docker-compose.simple.yml "$work/docker/compose/"
awk '
  /^## Quick Start$/ { section = 1; next }
  section && /^## / { exit }
  section && /^```bash$/ { block = 1; next }
  block && /^```$/ { exit }
  block { print }
' docker/README.md > "$work/quick-start.sh"
test -s "$work/quick-start.sh"
awk '
  /^## Quick Start \(Docker\)$/ { section = 1; next }
  section && /^## / { exit }
  section && /^```bash$/ { block = 1; next }
  block && /^```$/ { exit }
  block { print }
' README.md > "$work/docker-run-quick-start.sh"
test -s "$work/docker-run-quick-start.sh"
cd "$work"
unset SECRET VALKEY_PASSWORD COMPOSE_FILE COMPOSE_ENV_FILES COMPOSE_DISABLE_ENV_FILE

# Validate the actual Compose config in place of starting services.
docker() {
  case "$*" in
    'compose up')
      command docker compose config --quiet && printf 'checked\n' >> compose-checks
      ;;
    'compose -f - config --images') command docker "$@" ;;
    *) echo 'Unexpected Docker command in the Compose quick start' >&2; return 1 ;;
  esac
}
export -f docker

echo 'Checking fresh setup and rerun'
bash -e quick-start.sh
grep -Eq '^SECRET=[0-9a-f]{64}$' .env
grep -Eq '^VALKEY_PASSWORD=[0-9a-f]{64}$' .env
cp .env first.env
chmod 644 .env
bash -e quick-start.sh
cmp first.env .env
mode=$(stat -c %a .env 2>/dev/null || stat -f %Lp .env)
[[ "$mode" == 600 ]]
[[ $(wc -l < compose-checks) -eq 2 ]]

echo 'Checking a shared .env symlink remains untouched'
mv .env shared.env
chmod 640 shared.env
ln -s shared.env .env
bash -e quick-start.sh
cmp first.env shared.env
mode=$(stat -c %a shared.env 2>/dev/null || stat -f %Lp shared.env)
[[ "$mode" == 640 ]]
rm .env
mv shared.env .env

echo 'Checking missing keys are not appended through a symlink'
rm .env
printf '%s\n' 'SECRET=existing-secret' > shared.env
chmod 644 shared.env
ln -s shared.env .env
if bash -e quick-start.sh; then
  echo 'Expected the quick start to refuse a missing key in a linked env file' >&2
  exit 1
fi
[[ $(grep -c '^SECRET=' shared.env) -eq 1 ]]
[[ $(grep -c '^VALKEY_PASSWORD=' shared.env || true) -eq 0 ]]
mode=$(stat -c %a shared.env 2>/dev/null || stat -f %Lp shared.env)
[[ "$mode" == 644 ]]
rm .env shared.env
cp first.env .env

echo 'Checking empty shell overrides and a multiline dotenv value'
cat > .env <<'ENV'
SECRET=existing-secret
SAMPLE='multiline value
VALKEY_PASSWORD=example'
ENV
SECRET='' VALKEY_PASSWORD='' bash -e quick-start.sh
[[ $(grep -c '^SECRET=' .env) -eq 1 ]]
grep -qx 'SECRET=existing-secret' .env
grep -Eq '^VALKEY_PASSWORD=[0-9a-f]{64}$' .env

echo 'Checking keys configured in a different project directory'
printf '%s\n' 'COMPOSE_FILE=docker/compose/docker-compose.simple.yml' > .env
printf '%s\n' 'SECRET=project-secret' 'VALKEY_PASSWORD=project-valkey' > docker/compose/.env
cp .env before.env
cp docker/compose/.env project-before.env
bash -e quick-start.sh
cmp before.env .env
cmp project-before.env docker/compose/.env
[[ $(wc -l < compose-checks) -eq 5 ]]

echo 'Checking keys configured by the included stack'
printf '%s\n' 'HOST=localhost:3000' > .env
cp .env before.env
bash -e quick-start.sh
cmp before.env .env
cmp project-before.env docker/compose/.env
[[ $(wc -l < compose-checks) -eq 6 ]]

echo 'Checking a fresh setup with a custom Compose env file'
rm .env docker/compose/.env
printf '%s\n' 'SECRET=custom-secret' 'VALKEY_PASSWORD=custom-valkey' > custom.env
cp custom.env custom-before.env
COMPOSE_ENV_FILES=custom.env bash -e quick-start.sh
test -f .env
test ! -s .env
cmp custom-before.env custom.env
[[ $(wc -l < compose-checks) -eq 7 ]]

echo 'Checking a broken .env symlink cannot create its target'
rm .env
ln -s missing-target.env .env
if COMPOSE_ENV_FILES=custom.env bash -e quick-start.sh; then
  echo 'Expected the quick start to refuse a broken env symlink' >&2
  exit 1
fi
test ! -e missing-target.env
test -L .env

# Run the root README's actual Docker commands with Docker mocked. The shell
# still opens credential files, so this checks their real creation and reuse.
echo 'Checking root Docker quick-start key files'
mkdir "$work/docker-run"
cd "$work/docker-run"
docker() { printf '%s:%s\n' "$1" "${2:-}" >> docker-calls; }
chmod() {
  if [[ ${CHECK_FRESH_MODE:-} == 1 ]]; then
    if [[ $1 == 700 && $2 == .ots-key.* && $2 != */key ]] ||
       [[ $1 == 600 && $2 == .ots-key.*/key ]]; then
      printf '%s\n' "$1" >> private-chmod-checks
    else
      echo 'Fresh keys may be chmodded only inside their private staging directory' >&2
      return 1
    fi
  fi
  command chmod "$@"
}
export -f docker chmod
CHECK_FRESH_MODE=1 bash -e "$work/docker-run-quick-start.sh"
[[ $(cat private-chmod-checks) == $'700\n600\n700\n600' ]]
for key_file in .ots_redis_password .ots_secret; do
  [[ $(stat -c %a "$key_file" 2>/dev/null || stat -f %Lp "$key_file") == 600 ]]
  [[ $(cat "$key_file") =~ ^[0-9a-f]{64}$ ]]
  cp "$key_file" "$key_file.before"
  chmod 644 "$key_file"
done
bash -e "$work/docker-run-quick-start.sh"
for key_file in .ots_redis_password .ots_secret; do
  cmp "$key_file.before" "$key_file"
  [[ $(stat -c %a "$key_file" 2>/dev/null || stat -f %Lp "$key_file") == 600 ]]
done
[[ $(wc -l < docker-calls) -eq 6 ]]

echo 'Checking root Docker quick start refuses linked key files'
for key_file in .ots_redis_password .ots_secret; do
  rm "$key_file"
  printf 'unchanged\n' > victim
  chmod 640 victim
  ln -s victim "$key_file"
  if bash -e "$work/docker-run-quick-start.sh" > /dev/null 2>&1; then
    echo "Expected the quick start to refuse linked $key_file" >&2
    exit 1
  fi
  [[ $(cat victim) == unchanged ]]
  [[ $(stat -c %a victim 2>/dev/null || stat -f %Lp victim) == 640 ]]
  [[ $(wc -l < docker-calls) -eq 6 ]]
  rm "$key_file" victim
  mv "$key_file.before" "$key_file"
done

echo 'Checking a key file planted during generation is not followed'
rm .ots_secret
printf 'unchanged\n' > victim
openssl() {
  if [[ -n ${PLANT_KEY_LINK_TARGET:-} && -f .ots_redis_password && ! -e .ots_secret ]]; then
    ln -s "$PLANT_KEY_LINK_TARGET" .ots_secret
  fi
  command openssl "$@"
}
export -f openssl
if PLANT_KEY_LINK_TARGET=victim bash -e "$work/docker-run-quick-start.sh" > /dev/null 2>&1; then
  echo 'Expected the quick start to refuse a key symlink planted during generation' >&2
  exit 1
fi
[[ $(cat victim) == unchanged ]]
[[ $(wc -l < docker-calls) -eq 6 ]]
[[ -z $(find . -maxdepth 1 -name '.ots-key.*' -print) ]]

echo 'Checking a FIFO symlink planted during generation cannot receive the key'
rm .ots_secret victim
mkfifo victim.pipe
cat victim.pipe > fifo-captured & reader=$!
if PLANT_KEY_LINK_TARGET=victim.pipe bash -e "$work/docker-run-quick-start.sh" > /dev/null 2>&1; then
  echo 'Expected the quick start to refuse a FIFO symlink planted during generation' >&2
  exit 1
fi
kill "$reader" 2>/dev/null || true
wait "$reader" 2>/dev/null || true
[[ ! -s fifo-captured ]]
[[ $(wc -l < docker-calls) -eq 6 ]]
[[ -z $(find . -maxdepth 1 -name '.ots-key.*' -print) ]]
rm .ots_secret victim.pipe fifo-captured

echo 'Checking a symlink to a directory cannot receive the key'
mkdir receiver
if PLANT_KEY_LINK_TARGET=receiver bash -e "$work/docker-run-quick-start.sh" > /dev/null 2>&1; then
  echo 'Expected the quick start to refuse a directory symlink planted during generation' >&2
  exit 1
fi
[[ -z $(ls -A receiver) ]]
[[ $(wc -l < docker-calls) -eq 6 ]]
[[ -z $(find . -maxdepth 1 -name '.ots-key.*' -print) ]]
rm .ots_secret
rmdir receiver

echo 'Checking the quick start refuses a directory writable by other users'
chmod 777 .
if bash -e "$work/docker-run-quick-start.sh" > /dev/null 2>&1; then
  echo 'Expected the quick start to refuse a shared directory' >&2
  exit 1
fi
chmod 755 .
[[ ! -e .ots_secret ]]
[[ $(wc -l < docker-calls) -eq 6 ]]

echo 'Checking a private directory under a non-sticky shared parent is refused'
mkdir "$work/shared-parent"
chmod 777 "$work/shared-parent"
mkdir "$work/shared-parent/private-child"
chmod 700 "$work/shared-parent/private-child"
if (cd "$work/shared-parent/private-child" &&
    bash -e "$work/docker-run-quick-start.sh" > /dev/null 2>&1); then
  echo 'Expected the quick start to refuse an unprotected parent directory' >&2
  exit 1
fi
[[ ! -e "$work/shared-parent/private-child/.ots_redis_password" ]]

echo 'Checking a private directory under a sticky shared parent is accepted'
mkdir "$work/sticky-parent"
chmod 1777 "$work/sticky-parent"
mkdir "$work/sticky-parent/private-child"
chmod 700 "$work/sticky-parent/private-child"
(cd "$work/sticky-parent/private-child" && bash -e "$work/docker-run-quick-start.sh")
[[ $(stat -c %a "$work/sticky-parent/private-child/.ots_secret" 2>/dev/null ||
     stat -f %Lp "$work/sticky-parent/private-child/.ots_secret") == 600 ]]

echo 'Checking an unrelated ancestor owner is refused even with mode 0755'
mkdir "$work/foreign-parent"
mkdir "$work/foreign-parent/private-child"
chmod 755 "$work/foreign-parent"
chmod 700 "$work/foreign-parent/private-child"
(
  FORGED_PARENT=$(cd "$work/foreign-parent" && pwd -P)
  export FORGED_PARENT
  stat() {
    if [[ "$*" == *" $FORGED_PARENT" ]]; then
      printf '99999 40755\n'
    else
      command stat "$@"
    fi
  }
  export -f stat
  cd "$work/foreign-parent/private-child"
  if bash -e "$work/docker-run-quick-start.sh" > /dev/null 2>&1; then
    echo 'Expected the quick start to refuse an unrelated parent owner' >&2
    exit 1
  fi
  [[ ! -e .ots_redis_password ]]
)

if [[ $(uname -s) == Darwin ]]; then
  echo 'Checking an ACL-free pathname containing allow is accepted'
  mkdir "$work/ots allow check"
  chmod 700 "$work/ots allow check"
  [[ $(ls -lde "$work/ots allow check") != *$'\n'* ]]
  (cd "$work/ots allow check" && bash -e "$work/docker-run-quick-start.sh")
  [[ -f "$work/ots allow check/.ots_secret" ]]

  echo 'Checking an allow ACL is refused despite private mode bits'
  mkdir "$work/acl-parent"
  mkdir "$work/acl-parent/private-child"
  chmod 700 "$work/acl-parent" "$work/acl-parent/private-child"
  chmod +a 'everyone allow add_file,list,search,delete_child' "$work/acl-parent"
  [[ $(stat -f %Lp "$work/acl-parent") == 700 ]]
  if (cd "$work/acl-parent/private-child" &&
      bash -e "$work/docker-run-quick-start.sh" > /dev/null 2>&1); then
    echo 'Expected the quick start to refuse an ACL-bearing parent' >&2
    exit 1
  fi
  [[ ! -e "$work/acl-parent/private-child/.ots_redis_password" ]]

  echo 'Checking a deny-only ACL on an ancestor is accepted'
  mkdir "$work/deny-parent"
  mkdir "$work/deny-parent/private-child"
  chmod 700 "$work/deny-parent" "$work/deny-parent/private-child"
  chmod +a 'everyone deny delete' "$work/deny-parent"
  (cd "$work/deny-parent/private-child" && bash -e "$work/docker-run-quick-start.sh")
  [[ -f "$work/deny-parent/private-child/.ots_secret" ]]
  chmod -a# 0 "$work/deny-parent"

  echo 'Checking a deny-only ACL on the working directory is accepted'
  mkdir "$work/deny-cwd"
  chmod 700 "$work/deny-cwd"
  chmod +a 'everyone deny delete' "$work/deny-cwd"
  (cd "$work/deny-cwd" && bash -e "$work/docker-run-quick-start.sh")
  [[ -f "$work/deny-cwd/.ots_secret" ]]
  chmod -a# 0 "$work/deny-cwd"
fi

if [[ $(uname -s) == Linux ]] && command -v setfacl > /dev/null; then
  echo 'Checking keys remain private under a Linux default ACL'
  mkdir "$work/default-acl-parent"
  if setfacl -m d:g::r--,d:o::r-- "$work/default-acl-parent"; then
    (cd "$work/default-acl-parent" &&
      CHECK_FRESH_MODE=1 bash -e "$work/docker-run-quick-start.sh")
    [[ $(stat -c %a "$work/default-acl-parent/.ots_redis_password") == 600 ]]
    [[ $(stat -c %a "$work/default-acl-parent/.ots_secret") == 600 ]]
  else
    echo 'Skipping default ACL check: temporary filesystem does not support it'
  fi
fi
