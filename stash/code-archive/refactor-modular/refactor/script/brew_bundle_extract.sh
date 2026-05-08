#!/bin/ksh

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Extracts bundle IDs from various sources, filters out wildcards, deduplicates them,
# sorts by token, and outputs a structured YAML array.

typeset -a tokens_for_manual_review=()
json_output=""

# Process each JSON object from filtered brew info.
while IFS= read -r cask_json; do
  token=$(echo "$cask_json" | jq --raw-output '.token')
  typeset -a bundle_ids=()

  # (1) Collect bundle IDs from uninstall.signal.
  while IFS= read -r sb; do
    [[ -n "$sb" ]] && bundle_ids+=("$sb")
  done < <(echo "$cask_json" | jq --raw-output '.signal_bundles[]')

  # (2) Query osascript using the names field.
  while IFS= read -r name; do
    if [[ -n "$name" ]]; then
      bid=$(osascript -e "id of app \"$name\"" 2>/dev/null)
      if [[ $? -eq 0 && -n "$bid" ]]; then
        bundle_ids+=("$bid")
      fi
    fi
  done < <(echo "$cask_json" | jq --raw-output '.names[]')

  # (3) Process "app" artifacts (strip ".app", then query osascript).
  while IFS= read -r a_app; do
    if [[ -n "$a_app" ]]; then
      mod_app="${a_app%.app}"
      bid=$(osascript -e "id of app \"$mod_app\"" 2>/dev/null)
      if [[ $? -eq 0 && -n "$bid" ]]; then
        bundle_ids+=("$bid")
      fi
    fi
  done < <(echo "$cask_json" | jq --raw-output '.app_names[]')

  # (4) Collect bundle IDs from uninstall.quit entries.
  while IFS= read -r qbid; do
    [[ -n "$qbid" ]] && bundle_ids+=("$qbid")
  done < <(echo "$cask_json" | jq --raw-output '.quit_bundles[]')

  # Filter out any bundle IDs containing wildcards ("*").
  typeset -a filtered_bundle_ids=()
  for bid in "${bundle_ids[@]}"; do
    [[ "$bid" == *"*"* ]] && continue
    filtered_bundle_ids+=("$bid")
  done

  # Deduplicate and sort bundle IDs.
  unique_bundle_ids=($(printf "%s\n" "${filtered_bundle_ids[@]}" | sort --unique))

  if [[ ${#unique_bundle_ids[@]} -gt 0 ]]; then
    # Build a JSON object for this token.
    json_line=$(printf '{"token": "%s", "bundle_ids": [' "$token")
    first=1
    for bid in "${unique_bundle_ids[@]}"; do
      if [[ $first -eq 1 ]]; then
        first=0
      else
        json_line="${json_line},"
      fi
      json_line="${json_line}\"$bid\""
    done
    json_line="${json_line}]}"
    json_output+="$json_line"$'\n'
  else
    tokens_for_manual_review+=("$token")
  fi

done < <(
  brew info --cask --installed --json=v2 | \
  jq --compact-output '
    [.casks[] |
      # Exclude font casks.
      select(((.token | test("^font-")) and (.artifacts[]? | has("font"))) | not) |
      # Exclude casks composed entirely of unwanted artifact types.
      select((all(.artifacts[]?;
            has("qlplugin") or has("audiounitplugin") or has("colorpicker") or
            has("dictionary") or has("inputmethod") or has("prefpane") or
            has("zshcompletion") or has("fishcompletion") or has("bashcompletion")
           )) | not) |
      {
        token: .token,
        names: .name,
        # Process uninstall.signal: flatten uninstall field if it’s an array.
        signal_bundles: (
          [ .artifacts[]?
              | select(.uninstall != null)
              | (.uninstall | if type=="array" then .[] else . end)
              | select(has("signal"))
              | (if (.signal | type)=="array" then
                     if (.signal | length >= 2) then .signal[1] else empty end
                 else empty end)
          ]
        ),
        app_names: [ .artifacts[]? | select(has("app")) | .app[] ],
        # Process uninstall.quit: flatten uninstall field, then the quit array.
        quit_bundles: (
          [ .artifacts[]?
              | select(.uninstall != null)
              | (.uninstall | if type=="array" then .[] else . end)
              | select(has("quit"))
              | (.quit | if type=="array" then .[] else empty end)
          ]
        )
      }
    ] | sort_by(.token) | unique[]
  '
)

# Convert the JSON objects into a JSON array, deduplicate bundle_ids, and sort tokens.
final_json=$(echo "$json_output" | jq --slurp 'map(.bundle_ids |= (sort | unique)) | sort_by(.token)')

# Convert the final JSON array to pretty YAML.
echo "$final_json" | yq eval --prettyPrint '.'

# Print tokens needing manual review.
if [[ ${#tokens_for_manual_review[@]} -gt 0 ]]; then
  sorted_tokens=($(printf "%s\n" "${tokens_for_manual_review[@]}" | sort --unique))
  printf "\n\033[31;1mTokens needing manual review:\033[0m\n"
  for t in "${sorted_tokens[@]}"; do
    printf "\033[36m%s\033[0m\n" "$t"
 done
fi
