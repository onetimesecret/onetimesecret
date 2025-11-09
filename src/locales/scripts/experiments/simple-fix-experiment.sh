#!/bin/bash

# Simple experiment to fix type conflicts in locale files
# Focus on the specific conflicts we identified

BASELOCALE=${BASELOCALE:-"en"}
BASEPATH=${BASEPATH:-"src/locales/${BASELOCALE}.json"}
LOCALE="$1"

[ -z "$LOCALE" ] && echo "Usage: $0 LOCALE_FILE" >&2 && exit 1
[ ! -f "$LOCALE" ] && echo "File not found: $LOCALE" >&2 && exit 1

OUTPUT="${LOCALE%.json}.fixed.json"

echo "Simple conflict fix for $(basename "$LOCALE")..."

# Step 1: Show current conflicts
echo "Current conflicts:"
jq -n --slurpfile base "$BASEPATH" --slurpfile target "$LOCALE" '
def check_path($path):
  $path | split(".") as $keys |
  reduce $keys[] as $key ($base[0];
    if . == null then null
    elif type == "object" and has($key) then .[$key]
    else null end
  ) as $base_val |

  reduce $keys[] as $key ($target[0];
    if . == null then null
    elif type == "object" and has($key) then .[$key]
    else null end
  ) as $target_val |

  if $base_val == null or $target_val == null then
    empty
  elif ($base_val | type) != ($target_val | type) then
    {
      path: $path,
      base_type: ($base_val | type),
      target_type: ($target_val | type),
      base_value: (if ($base_val | type) == "string" then $base_val else null end),
      target_value: (if ($target_val | type) == "string" then $target_val else null end)
    }
  else
    empty
  end;

# Check known problem paths
[
  "web.colonel.dashboard",
  "web.colonel.welcome",
  "web.colonel.actions",
  "web.colonel.stats",
  "web.domains"
] | map(check_path(.)) | map(select(. != null))
' | jq -r '.[] | "  \(.path): \(.base_type) → \(.target_type)"'

# Step 2: Create a fixed version with simple strategy
echo "Applying fixes..."
jq --slurpfile base "$BASEPATH" '
# Strategy: When there is a type conflict, use the base structure and preserve target content elsewhere

# First, let me extract conflicting target content that we want to preserve
. as $target |

# Save conflicting object content before we lose it
($target.web.colonel.dashboard // {}) as $dashboard_content |
($target.web.colonel.welcome // {}) as $welcome_content |

# Now rebuild using base structure
$base[0] as $structure |

# Apply the base structure but preserve translations where possible
def apply_structure($struct; $trans):
  if ($struct | type) == "object" then
    if ($trans | type) == "object" then
      $struct | with_entries(
        .key as $k |
        .value as $v |
        .value = apply_structure($v; $trans[$k] // {})
      )
    else
      # Target is not object, use base structure with empty values
      $struct | with_entries(.value =
        if (.value | type) == "object" then
          .value | map_values("")
        else
          ""
        end
      )
    end
  else
    # Base is primitive - use target value if available and compatible
    if ($trans | type) == ($struct | type) then
      if $trans != null and $trans != "" then $trans else $struct end
    else
      $struct
    end
  end;

apply_structure($structure; $target) |

# Now merge back the preserved content to correct locations
if $dashboard_content != {} then
  .web.dashboard = ($dashboard_content + (.web.dashboard // {}))
else . end |

if $welcome_content != {} then
  .web.colonel.welcome_content = $welcome_content
else . end

' "$LOCALE" > "$OUTPUT"

if [ $? -eq 0 ]; then
  echo "✓ Fixed version created: $OUTPUT"

  # Quick validation
  if jq empty "$OUTPUT" 2>/dev/null; then
    echo "✓ Generated valid JSON"

    # Check specific fixes
    echo "Verification:"
    echo -n "  web.colonel.dashboard: "
    jq -r '.web.colonel.dashboard // "missing"' "$OUTPUT"
    echo -n "  web.colonel.welcome: "
    jq -r '.web.colonel.welcome // "missing"' "$OUTPUT"
    echo -n "  web.dashboard exists: "
    jq -r 'if .web.dashboard then "yes" else "no" end' "$OUTPUT"

  else
    echo "✗ Generated invalid JSON"
    exit 1
  fi
else
  echo "✗ Fix failed"
  exit 1
fi
