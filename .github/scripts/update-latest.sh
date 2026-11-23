#!/usr/bin/env bash
set -euo pipefail

# Finished jobs can arrive out of order. Compare both build numbers across all runs.
tag=$(
    gh api --paginate --slurp 'repos/{owner}/{repo}/releases?per_page=100' |
        jq -r '[
            .[][] | select(.draft == false and .prerelease == false)
            | select(.tag_name | test("\\Abuild-[0-9a-f]{40}\\z"))
            | (.name // "" | capture("\\AUnderwater · Build (?<run>[1-9][0-9]*)[.](?<position>[1-9][0-9]*)\\z")) as $build
            | {tag: .tag_name, number: [($build.run | tonumber), ($build.position | tonumber)]}
        ] | max_by(.number) | .tag // empty'
)
if [[ -n "$tag" ]]; then
    gh release edit "$tag" --latest
fi
