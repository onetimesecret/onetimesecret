#!/bin/bash

# Generate config files from mapping.yaml
# Usage: ./generate-config-from-mapping.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_EXAMPLE="$PROJECT_ROOT/etc/config.example.converted.yaml"
CONFIG_MAPPING="$PROJECT_ROOT/etc/config.mapping.yaml"
STATIC_OUTPUT="$PROJECT_ROOT/etc/config.static.yaml"
DYNAMIC_OUTPUT="$PROJECT_ROOT/etc/config.dynamic.yaml"

# Validate required files exist
if [[ ! -f "$CONFIG_EXAMPLE" ]]; then
    echo "Error: $CONFIG_EXAMPLE not found"
    exit 1
fi

if [[ ! -f "$CONFIG_MAPPING" ]]; then
    echo "Error: $CONFIG_MAPPING not found"
    exit 1
fi

echo "Generating configuration files from mappings..."

# Function to process mappings
process_mappings() {
    local mapping_type="$1"
    local output_file="$2"

    echo "Creating ${mapping_type} configuration..."

    # Initialize empty config file
    yq eval 'del(.[])'  <<< '{}' > "$output_file"

    # Get the count of mappings
    local count=$(yq eval ".mappings.${mapping_type} | length" "$CONFIG_MAPPING")

    if [[ "$count" == "null" || "$count" == "0" ]]; then
        echo "  No ${mapping_type} mappings found"
        return
    fi

    # Process each mapping
    for ((i=0; i<count; i++)); do
        local from_path=$(yq eval ".mappings.${mapping_type}[$i].from" "$CONFIG_MAPPING")
        local to_path=$(yq eval ".mappings.${mapping_type}[$i].to" "$CONFIG_MAPPING")

        if [[ "$from_path" == "null" || "$to_path" == "null" ]]; then
            echo "  Warning: Skipping invalid mapping at index $i"
            continue
        fi

        # Handle wildcard mappings (ending with .)
        if [[ "$from_path" == *. ]]; then
            from_path="${from_path%.*}"
        fi

        echo "  Mapping: $from_path -> $to_path"

        # Generate and execute yq command
        local cmd="yq eval '.${to_path} = load(\"${CONFIG_EXAMPLE}\").${from_path}' -i \"${output_file}\""

        # Execute the command
        if ! yq eval ".${to_path} = load(\"${CONFIG_EXAMPLE}\").${from_path}" -i "$output_file" 2>/dev/null; then
            echo "    Warning: Failed to map $from_path -> $to_path (source may not exist)"
        fi
    done
}

# Process static mappings
process_mappings "static" "$STATIC_OUTPUT"

# Process dynamic mappings
process_mappings "dynamic" "$DYNAMIC_OUTPUT"

echo "Configuration generation completed!"
echo "Static config: $STATIC_OUTPUT"
echo "Dynamic config: $DYNAMIC_OUTPUT"

# Show structure of generated files
if [[ -f "$STATIC_OUTPUT" ]]; then
    echo ""
    echo "Static config structure:"
    yq eval 'keys' "$STATIC_OUTPUT" || echo "  (empty or invalid)"
fi

if [[ -f "$DYNAMIC_OUTPUT" ]]; then
    echo ""
    echo "Dynamic config structure:"
    yq eval 'keys' "$DYNAMIC_OUTPUT" || echo "  (empty or invalid)"
fi

echo ""
echo "To regenerate after mapping changes, simply run this script again."
