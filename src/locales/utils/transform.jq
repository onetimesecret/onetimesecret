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
