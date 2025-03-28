# Onetime - RSPEC README


## Window JSON

For v0.21.0, we are refactoring the base view heavily and want to make sure we produce the exact same results. We can do this by comparing the JSON that view generates before and after. Or more likely, before with during, and after.

The JSON file has samples of the actual JSON objects, of which there are two structures: when logged out and when logged in. We need a test for both.

```bash
# Colorized output
diff --color <(jq --sort-keys . window-authenticated-develop.json) <(jq --sort-keys . window-authenticated-1187.json)

# Side-by-side comparison
diff --side-by-side <(jq --sort-keys . window-authenticated-develop.json) <(jq --sort-keys . window-authenticated-1187.json)

# Unified format (more compact)
diff -u <(jq --sort-keys . window-authenticated-develop.json) <(jq --sort-keys . window-authenticated-1187.json)
```
