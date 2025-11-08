#!/bin/bash

# Experimental script to fix structural conflicts in locale files
# This script attempts to resolve type mismatches between base and target files

BASELOCALE=${BASELOCALE:-"en"}
BASEPATH=${BASEPATH:-"src/locales/${BASELOCALE}.json"}
LOCALE="$1"

[ -z "$LOCALE" ] && echo "Usage: $0 LOCALE_FILE" >&2 && exit 1
[ ! -f "$LOCALE" ] && echo "File not found: $LOCALE" >&2 && exit 1
[ ! -f "$BASEPATH" ] && echo "Base file not found: $BASEPATH" >&2 && exit 1

OUTPUT="${LOCALE%.json}.fixed.json"

echo "Experimenting with conflict resolution for $(basename "$LOCALE")..."

# Strategy 1: Detect and resolve type conflicts
jq_fix_conflicts='
def detect_type_conflicts($base; $target; $path):
  if ($base | type) == "object" and ($target | type) == "object" then
    ($base | keys[]) as $k |
    if $target | has($k) then
      detect_type_conflicts($base[$k]; $target[$k]; $path + [$k])
    else
      {conflict: "missing_key", path: ($path + [$k] | join(".")), base_type: ($base[$k] | type)}
    end
  elif ($base | type) == "string" and ($target | type) == "object" then
    {conflict: "base_string_target_object", path: ($path | join(".")), base_value: $base, target_keys: ($target | keys)}
  elif ($base | type) == "object" and ($target | type) == "string" then
    {conflict: "base_object_target_string", path: ($path | join(".")), base_keys: ($base | keys), target_value: $target}
  else
    empty
  end;

def resolve_conflicts($base; $target; $conflicts):
  $conflicts | group_by(.conflict) | map({
    type: .[0].conflict,
    count: length,
    items: map({path: .path, details: (del(.conflict) | del(.path))})
  });

def fix_structure($base; $target):
  [detect_type_conflicts($base; $target; [])] as $conflicts |

  # Show what we found
  ($conflicts | length) as $conflict_count |
  if $conflict_count > 0 then
    ("Found " + ($conflict_count | tostring) + " conflicts:") | debug |
    ($conflicts | group_by(.conflict) | map("\(.length) \(.[0].conflict) conflicts") | join(", ")) | debug
  else
    "No conflicts found" | debug
  end |

  # Strategy: Use base structure, preserve target values where possible
  def walk_and_fix($b; $t):
    if ($b | type) == "object" then
      if ($t | type) == "object" then
        # Both objects - recurse normally
        $b | with_entries(
          .key as $k |
          .value as $v |
          {
            key: $k,
            value: (
              if $t | has($k) then
                walk_and_fix($v; $t[$k])
              else
                # Missing in target - use empty structure or base value
                if ($v | type) == "object" then
                  $v | map_values(empty)
                else
                  ""
                end
              end
            )
          }
        )
      else
        # Base is object, target is primitive - use base structure with empty values
        ("Base is object, target is " + ($t | type) + " - using base structure") | debug |
        $b | map_values(
          if type == "object" then
            map_values(empty)
          else
            ""
          end
        )
      end
    else
      # Base is primitive
      if ($t | type) == "object" then
        # Base is primitive, target is object - use base primitive value
        ("Base is " + ($b | type) + ", target is object - using base value") | debug |
        $b
      else
        # Both primitives - prefer target if not empty
        if $t != "" then $t else $b end
      end
    end;

  walk_and_fix($base; $target);

# Main execution
$target[0] | fix_structure($base[0]; .)
'

echo "Running conflict resolution..."
if jq -n --slurpfile base "$BASEPATH" --slurpfile target "$LOCALE" "$jq_fix_conflicts" > "$OUTPUT" 2>&1; then
  echo "✓ Fixed version created: $OUTPUT"

  echo "Checking if conflicts are resolved..."
  SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
  if [ -x "$SCRIPT_DIR/debug-locale-structure.sh" ]; then
    echo "Before fix:"
    "$SCRIPT_DIR/debug-locale-structure.sh" -q "$LOCALE" && echo "  No conflicts" || echo "  Had conflicts"

    echo "After fix:"
    BASEPATH="$BASEPATH" "$SCRIPT_DIR/debug-locale-structure.sh" -q "$OUTPUT" && echo "  ✓ Conflicts resolved!" || echo "  ⚠ Still has conflicts"
  fi

  echo "Differences between original and fixed:"
  echo "Original structure conflicts:"
  jq -n --slurpfile base "$BASEPATH" --slurpfile orig "$LOCALE" '
    def find_conflicts($base; $target; $path):
      if ($base | type) == "object" and ($target | type) == "object" then
        ($base | keys[]) as $k |
        if $target | has($k) then
          find_conflicts($base[$k]; $target[$k]; $path + [$k])
        else
          empty
        end
      elif ($base | type) != ($target | type) then
        ($path | join(".")) + " (" + ($base | type) + " vs " + ($target | type) + ")"
      else
        empty
      end;
    [find_conflicts($base[0]; $orig[0]; [])]
  ' | jq -r '.[] | "  • " + .'

else
  echo "✗ Conflict resolution failed"
  echo "Error output:"
  cat "$OUTPUT"
  rm -f "$OUTPUT"
  exit 1
fi
