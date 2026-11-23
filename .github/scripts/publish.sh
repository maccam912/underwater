#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
failed=0
for directory in releases/*; do
    commit=$(basename "$directory")
    for os in macos windows; do
        receipt="$PWD/native-passes/$commit/$os.sha256"
        if [[ ! -s "$receipt" ]] || ! (cd "$directory" && sha256sum --strict --check "$receipt"); then
            echo "::error::Missing or mismatched $os startup verification for $commit"
            failed=1
            continue 2
        fi
    done
    index=$(jq -er --arg sha "$commit" '.[] | select(.sha == $sha) | .index' <<< "$COMMIT_BATCH")
    title="Underwater · Build $GITHUB_RUN_NUMBER.$((index + 1))"
    tag="build-$commit"
    # Keep one release per source commit, including on a later workflow dispatch.
    if draft=$(gh release view "$tag" --json isDraft --jq .isDraft); then
        if [[ "$draft" == false ]]; then
            continue
        fi
    else
        gh release create "$tag" --target "$commit" --draft --title "$title" \
            --notes "Playable builds of commit \`$commit\` for Android (ARM), Linux and Windows (x86-64), and macOS (Universal)."
    fi
    gh release upload "$tag" "$directory"/* --clobber
    gh release edit "$tag" --title "$title" --draft=false --prerelease=false --latest=false
done
exit "$failed"
