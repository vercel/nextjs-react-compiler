# This repo vendors the React Compiler (Rust port) from react/react main
# into ./react-compiler, then (editing only Cargo.toml for crate naming) sets each
# crate's published name to `nextjs_react_compiler_*` while keeping the lib/import
# name, source, and directories as upstream's `react_compiler_*`, and adds the
# metadata + `publish` flags to release `nextjs_react_compiler` and its deps to crates.io.
#
# The core compiler crates live in react/react:compiler/crates/. The SWC integration
# crate (react_compiler_swc) was moved to swc-project/swc:crates/swc_ecma_react_compiler;
# `sync` pulls from both repos and overlays the swc crate on top of the react/react snapshot.
#
# The oxc-project org ruleset forbids merge commits, so the vendor is a linear
# snapshot (not `git subtree`): each `sync` re-extracts upstream's `compiler/`,
# re-runs the transform tool (./codemod), re-applies ./patches, and commits once.
# Both are re-applied every sync because the snapshot is taken fresh.
#
#   just import       # one-time: create ./react-compiler (transformed)
#   just sync         # update ./react-compiler from both upstreams, re-transform, commit
#   just sync-react   # extract react/react compiler crates only (no commit)
#   just sync-swc     # extract swc-project/swc integration crate only (no commit)
#   just codemod      # (re)run codemod on ./react-compiler in place
#   just patch        # apply ./patches/*.patch (Rust source changes the codemod can't express)
#   just check        # cargo check the vendored workspace
#   just publish-dry  # dry-run publishing the whole set (cargo release-oxc publish --dry-run)
#   just publish      # publish nextjs_react_compiler + its deps via cargo-release-oxc
#   just status       # show which upstream commit is currently vendored

react_repo    := "https://github.com/react/react.git"
upstream_ref  := "main"
src_dir       := "compiler"          # path of the compiler inside the react monorepo
prefix        := "react-compiler"    # where it lives in THIS repo

swc_repo  := "https://github.com/swc-project/swc.git"
swc_ref   := "main"
swc_src   := "crates/swc_ecma_react_compiler"  # path within swc-project/swc
swc_dest  := "react_compiler_swc"              # crate directory name in this repo

# Show available recipes
default:
    @just --list

# One-time import (same operation as sync; kept for discoverability)
import: sync

# Full sync: extract both upstreams, transform, patch, and commit.
sync:
    #!/usr/bin/env bash
    set -euo pipefail
    # Read from HEAD so a partially-applied prior sync can't leave a stale version on disk.
    version="$(git show HEAD:{{prefix}}/Cargo.toml 2>/dev/null | sed -n 's/^version = "\(.*\)"/\1/p' | head -1)"
    version="${version:-0.1.0}"

    just sync-react
    react_sha="$(git rev-parse FETCH_HEAD)"

    just sync-swc
    swc_sha="$(git rev-parse FETCH_HEAD)"

    just codemod "$version"
    just patch
    git add -A {{prefix}}
    if git diff --cached --quiet -- {{prefix}}; then
        echo "{{prefix}} already up to date — nothing to commit."
    else
        git commit -q -m "vendor: react-compiler @ ${react_sha} swc @ ${swc_sha}"
        echo "Committed {{prefix}} @ react:${react_sha} swc:${swc_sha}."
    fi

# Extract the React compiler crates from react/react into ./{{prefix}}.
# Wipes and re-extracts the full tree; run sync-swc afterward to overlay the SWC crate.
sync-react:
    #!/usr/bin/env bash
    set -euo pipefail
    git fetch --depth=1 --no-tags {{react_repo}} {{upstream_ref}}
    upstream="$(git rev-parse FETCH_HEAD)"
    tree="$(git rev-parse "FETCH_HEAD:{{src_dir}}")"
    git rm -r --cached -f --quiet --ignore-unmatch {{prefix}}
    rm -rf {{prefix}}
    git read-tree --prefix={{prefix}}/ -u "$tree"
    echo "sync-react: {{prefix}} from {{react_repo}} @ ${upstream}"

# Extract the SWC integration crate from swc-project/swc into ./{{prefix}}/crates/{{swc_dest}}.
# The SWC crate was moved out of react/react; this overlays it on top of a sync-react extraction.
sync-swc:
    #!/usr/bin/env bash
    set -euo pipefail
    git fetch --depth=1 --no-tags {{swc_repo}} {{swc_ref}}
    swc_upstream="$(git rev-parse FETCH_HEAD)"
    swc_tree="$(git rev-parse "FETCH_HEAD:{{swc_src}}")"
    dest="{{prefix}}/crates/{{swc_dest}}"
    git rm -r --cached -f --quiet --ignore-unmatch "$dest"
    rm -rf "$dest"
    git read-tree --prefix="$dest/" -u "$swc_tree"
    just _fixup-swc-cargo "$dest/Cargo.toml"
    echo "sync-swc: {{swc_dest}} from {{swc_repo}} @ ${swc_upstream}"

# Post-process the upstream swc crate's Cargo.toml to fit our workspace:
#   - rename from the swc upstream name to our crate name (codemod adds the nextjs_ prefix)
#   - strip monorepo path deps, leaving only the crates.io version
#   - resolve swc-workspace-inherited deps to explicit crates.io versions
#   - drop [dev-dependencies] (swc-internal test harness not available on crates.io)
_fixup-swc-cargo cargo:
    #!/usr/bin/env bash
    set -euo pipefail
    cargo="{{cargo}}"
    # All sed substitutions in one pass → temp file → replace (avoids BSD/GNU -i differences)
    sed -E \
        -e 's/^(name[[:space:]]*=[[:space:]]*)"swc_ecma_react_compiler"/\1"react_compiler_swc"/' \
        -e 's/,[[:space:]]*path[[:space:]]*=[[:space:]]*"[^"]*"//g' \
        -e 's/^(rustc-hash[[:space:]]*=[[:space:]]*)\{[^}]*workspace[^}]*\}/\1"2"/' \
        -e 's/^(serde[[:space:]]*=[[:space:]]*)\{[^}]*workspace[^}]*\}/\1{ version = "1", features = ["derive"] }/' \
        -e 's/^(serde_json[[:space:]]*=[[:space:]]*)\{[^}]*workspace[^}]*\}/\1"1"/' \
        -e 's/^(indexmap[[:space:]]*=[[:space:]]*)\{[^}]*workspace[^}]*\}/\1{ version = "2", features = ["serde"] }/' \
        -e 's/^(swc_atoms[[:space:]]*=[[:space:]]*)\{[^}]*\}/\1"9"/' \
        -e 's/^(swc_common[[:space:]]*=[[:space:]]*)\{[^}]*\}/\1"21"/' \
        -e 's/^(swc_ecma_ast[[:space:]]*=[[:space:]]*)\{[^}]*\}/\1"23"/' \
        -e 's/^(swc_ecma_codegen[[:space:]]*=[[:space:]]*)\{[^}]*\}/\1"26"/' \
        -e 's/^(swc_ecma_parser[[:space:]]*=[[:space:]]*)\{[^}]*\}/\1"39"/' \
        -e 's/^(swc_ecma_visit[[:space:]]*=[[:space:]]*)\{[^}]*\}/\1"23"/' \
        "$cargo" > "${cargo}.tmp" && mv "${cargo}.tmp" "$cargo"
    # Drop [dev-dependencies] section — the `testing` crate is swc-internal and not on crates.io
    awk '/^\[dev-dependencies\]/{skip=1; next} skip && /^\[/{skip=0} !skip{print}' "$cargo" > "${cargo}.tmp" && mv "${cargo}.tmp" "$cargo"

# (Re)run codemod on ./{{prefix}}: published names, workspace deps, publish flags, LICENSE, oxc_release.toml.
# `version` defaults to the version already in the tree (cargo-release-oxc owns the bumps).
codemod version=`sed -n 's/^version = "\(.*\)"/\1/p' react-compiler/Cargo.toml 2>/dev/null | head -1`:
    cargo run --quiet -p codemod -- {{prefix}} {{version}}

# Apply local source patches in ./patches over the freshly-synced upstream tree.
# These are changes the codemod can't express (Rust source, not Cargo.toml) — e.g.
# having `compile_program` return the compiled AST by value instead of a JSON
# string, so the oxc/swc front-ends skip a serialize→deserialize round-trip.
# `git apply` fails loudly if upstream drifts, so a stale patch surfaces at sync.
patch:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    for p in patches/*.patch; do
        echo "Applying $p"
        git apply "$p"
    done

# Type-check the vendored workspace
check:
    cd {{prefix}} && cargo check --workspace

# Dry-run publish — same code path as `publish` but with --dry-run, so failures
# (publish order, metadata validation, etc.) surface here instead of mid-publish.
publish-dry:
    cd {{prefix}} && cargo release-oxc publish --release crates --dry-run

# Needs cargo-release-oxc (`cargo install --git https://github.com/oxc-project/cargo-release-oxc`),
# a clean git tree, and CARGO_REGISTRY_TOKEN.
# Publish nextjs_react_compiler + its deps in order, skipping publish=false crates
publish:
    cd {{prefix}} && cargo release-oxc publish --release crates

# Show the upstream commit currently vendored
status:
    #!/usr/bin/env bash
    set -euo pipefail
    line="$(git log -1 --grep='^vendor: react-compiler' --format='%h  %ci%n%s' 2>/dev/null || true)"
    if [ -n "$line" ]; then echo "$line"; else echo "Nothing vendored yet — run 'just import'."; fi
