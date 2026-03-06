#!/usr/bin/env bash

# install-dev.sh
#
# Run this in any checkout/worktree to set up a local dev environment:
#   - Copies Procfile.dev.example -> Procfile.dev (if not present)
#   - Links shared dev resources from OTS_DEV_CONFIG
#   - Installs Ruby gems (bundle install)
#   - Installs Node packages (pnpm install)
#
# Idempotent: safe to re-run at any time.

set -euo pipefail

OTS_DEV_CONFIG="${OTS_DEV_CONFIG:-$HOME/.config/onetimesecret-dev}"

# Files/dirs to symlink: local_path -> shared_path
declare -A LINKS=(
    ["data"]="data"
    [".env.test"]=".env.test"
    ["etc/puma.rb"]="puma.rb"
)

# Optional: .env if you have one
if [[ -f "$OTS_DEV_CONFIG/.env" ]]; then
    LINKS[".env"]=".env"
fi

# Copy Procfile.dev.example -> Procfile.dev if not already present
setup_procfile_dev() {
    if [[ ! -f "Procfile.dev.example" ]]; then
        echo "Skip: Procfile.dev.example does not exist"
        return
    fi

    if [[ -f "Procfile.dev" ]]; then
        echo "OK:   Procfile.dev (already exists)"
        return
    fi

    cp -n "Procfile.dev.example" "Procfile.dev"
    echo "Copy: Procfile.dev.example -> Procfile.dev"
}

setup_puma_rb() {
    if [[ ! -f "etc/examples/puma.example.rb" ]]; then
        echo "Skip: etc/examples/puma.example.rb does not exist"
        return
    fi

    if [[ -f "etc/puma.rb" || -L "etc/puma.rb" ]]; then
        echo "OK:   etc/puma.rb (already exists)"
        return
    fi

    cp -n "etc/examples/puma.example.rb" "etc/puma.rb"
    echo "Copy: etc/examples/puma.example.rb -> etc/puma.rb"
}

# Repair .env.sh if it's a symlink (historical git issue)
repair_env_sh() {
    if [[ -L ".env.sh" ]]; then
        echo "Repairing .env.sh (removing stale symlink)..."
        rm ".env.sh"
    fi

    if [[ ! -f ".env.sh" ]]; then
        echo "Creating .env.sh wrapper..."
        cat > ".env.sh" << 'EOF'
#!/usr/bin/env bash
# .env.sh

# A convenience wrapper so that .env is just a basic environment file
# that is compatible everywhere while still using the auto-export
# functionality the shell gods left for us.

# set -a enables automatic export mode. All variable assignments between
# here and and set +a will be exported to child processes without needing
# 'export' keyword.
set -a

# Load the vars
[ -f .env ] && source .env

# Set +a restores default behavior where variables must be explicitly exported
set +a
EOF
        chmod +x ".env.sh"
        echo "Created and marked executable: .env.sh"
    fi
}

link_resource() {
    local local_path="$1"
    local shared_name="$2"
    local target="$OTS_DEV_CONFIG/$shared_name"

    # Validate target is within expected config directory (prevent path traversal)
    case "$target" in
        "$OTS_DEV_CONFIG"/*) ;;
        *) echo "Error: Invalid target path: $target"; return 1 ;;
    esac

    if [[ ! -e "$target" ]]; then
        echo "Skip: $target does not exist"
        return
    fi

    # Already correctly linked
    if [[ -L "$local_path" && "$(readlink "$local_path")" == "$target" ]]; then
        echo "OK:   $local_path -> $target"
        return
    fi

    # Exists but not a symlink - back it up
    if [[ -e "$local_path" && ! -L "$local_path" ]]; then
        local backup="${local_path}.bak.$(date +%Y%m%d-%H%M%S)"
        echo "Backup: $local_path -> $backup"
        mv "$local_path" "$backup"
    fi

    # Remove stale symlink
    if [[ -L "$local_path" ]]; then
        rm "$local_path"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$local_path")"

    ln -s "$target" "$local_path"
    echo "Link: $local_path -> $target"
}

# Sanity check
if [[ ! -f "Gemfile" ]]; then
    echo "Error: Run this from an OTS checkout root"
    exit 1
fi

# Copy Procfile.dev from example if not present
setup_procfile_dev

# Copy puma.rb from example if not present
setup_puma_rb

# Repair .env.sh before proceeding with other links
repair_env_sh

echo "Linking dev resources from $OTS_DEV_CONFIG"
echo "---"

for local_path in "${!LINKS[@]}"; do
    link_resource "$local_path" "${LINKS[$local_path]}"
done

echo "---"
echo "Installing Ruby gems..."
bundle install

echo "---"
echo "Installing Node packages..."
pnpm install

echo "---"
echo "Done. Run 'bin/dev' to start."
