# Onetime Secret Locales

This directory contains the locales for the Onetime Secret project in JSON format.

## Structure

## QA

### Commands

#### Create a flattened keymap from the base locale:

```bash
jq -r 'paths(scalars) as $p | [$p[] | tostring] | join(".")' en.json > keys.txt
```

#### Create a flattened keymap with values from the base locale:

```bash
jq -r '
def flatten:
  . as $root
  | paths(scalars) as $path
  | ($path | join(".")) + "\t" + ($root | getpath($path) | tostring)
;
flatten
' src/locales/en.json > flat_values.tsv
```

#### Validate structure matches:

```bash
jq -r 'paths(scalars)' en.json > base_paths.txt
jq -r 'paths(scalars)' fr.json > target_paths.txt
diff base_paths.txt target_paths.txt
```

#### Statistics generation:

```bash
jq -r '
  def count_empty:
    if type == "object" then
      reduce (to_entries[]) as $item (
        0;
        . + ($item.value | count_empty)
      )
    elif . == "" then 1
    else 0
    end;

  [paths(scalars)] as $paths |
  length as $total |
  count_empty as $empty |
  {
    "total": $total,
    "empty": $empty,
    "completed": (($total-$empty)/$total*100)
  }
' src/locales/en.json > stats.json
```

#### Transform

```jq
# src/locales/utils/transform.jq

# About: Transform that JSON structure to match this JSON structure
# Usage: jq -f transform.jq --argfile base en.json fr.json > fr.transformed.json
# Language: `jq`, a domain-specific language for processing JSON data.

# Performs recursive traversal of nested JSON structures
# Applies transformation function f to each scalar value
# Returns transformed object maintaining original structure
def walk(f):
  . as $in
  | if type == "object" then
      reduce keys[] as $key
        ( {}; . + { ($key):  ($in[$key] | walk(f)) } )
    else if type == "array" then map( walk(f) )
    else f
    end
end;

# $base: Source locale structure to match
# Input: Target locale to transform
# Output: Transformed target matching source structure
input as $base |
walk(
  if type != "object" and type != "array" then
    if . != null then .
    else $base[getpath(path)]
    end
  else .
  end
)
```

## References

- [JSON i18n](https://phrase.com/blog/posts/json-i18n/)
