# Onetime Secret Locales

This directory contains the locales for the Onetime Secret project in JSON format.

## Structure

## QA

### Commands

#### 1. Create a flattened keymap from the base locale:

```bash
jq -r 'paths(scalars) as $p | [$p[] | tostring] | join(".")' src/locales/en.json > keys.txt
```
The output will be:

```
web.COMMON.broadcast
web.COMMON.button_generate_secret_short
web.COMMON.generate_password_disabled
...
```

Alternately, create a flattened keymap with values from the base locale:

```bash
jq -r '
def flatten:
  . as $root
  | paths(scalars) as $path
  | ($path | join(".")) + "\t" + ($root | getpath($path) | tostring)
;
flatten
' src/locales/en.json > keys_with_values.txt
```

The output will be:

```
web.COMMON.broadcast ""
web.COMMON.button_generate_secret_short "Generate"
web.COMMON.generate_password_disabled "Generate password is disabled"
...
```

#### 2. Transform the keys list into JSON


```bash
# 1. Reads raw input (-R)
# 2. Collects all input into a single string (-s)
# 3. Splits into array by newlines
# 4. Filters empty lines
# 5. Maps each key to object with required structure
# 6. Wraps in a container object with "keys" property
cat keys.txt | jq -R -s '
  split("\n")
  | map(select(length > 0))
  | map({
      oldkey: .,
      files: [],
      count: 0,
      newkey: null
    })
  | {keys: .}
' > keys.json
```

The output structure will be:

```json
{
  "keys": [
    {
      "oldkey": "web.COMMON.broadcast",
      "files": [],
      "count": 0,
      "newkey": null
    },
    {
      "oldkey": "web.COMMON.button_generate_secret_short",
      "files": [],
      "count": 0,
      "newkey": null
    }
    // ...
  ]
}
```

#### 3. Update the files list for each key

```bash
$ src/locales/scripts/search-key-usage
```

#### 4. Sort keys.json by number of files

```bash
jq '
.keys |= map(. + {count: (.files | length)}) |
.keys |= sort_by(.count) |
.keys |= reverse
' keys.json > keys_sorted.json
```


### Adhoc commands

#### List 2nd level keys:

This extracts and displays arrays of second-level key names found under 'web' and 'email' top-level keys.

```bash
jq '{web: .web | keys, email: .email | keys}' src/locales/en.json
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
