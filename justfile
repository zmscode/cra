# Cra tasks. Run `just` to list them.

set shell := ["bash", "-euo", "pipefail", "-c"]

upstream_branch := "upstream/main"

[private]
default:
    @just --list --unsorted

# --- Build & run -------------------------------------------------------------

# Build build/Cra.app (config: release | debug)
build config="release":
    scripts/build.sh {{config}}

# Debug build of build/Cra.app
debug:
    scripts/build.sh debug

# Launch build/Cra.app, building it first if missing
run:
    scripts/run.sh

# Force a rebuild, then launch (config: release | debug)
rebuild config="release":
    scripts/run.sh --rebuild {{config}}

# Dev loop: debug CraDev.app, rebuilds + relaunches on save
dev:
    scripts/dev.sh

# Build and launch CraDev.app once, logs in this terminal
dev-once:
    scripts/dev.sh --once

# Compile the Swift package only (no app bundle)
check config="debug":
    swift build -c {{config}}

# Download CEF and Sparkle if they're missing
fetch:
    scripts/fetch-cef.sh
    scripts/fetch-sparkle.sh

# Delete build outputs (keeps vendor/ downloads)
clean:
    rm -rf build .build

# Delete build outputs and vendored CEF/Sparkle
clean-all: clean
    rm -rf vendor

# Sign, notarize and package into build/dist (see docs/release.md)
release:
    scripts/release.sh

# --- Upstream (VictorKildahl/cra) -------------------------------------------

# Fetch upstream without changing anything
upstream-fetch:
    git fetch upstream

# Show commits upstream has that you don't, and vice versa
upstream-status: upstream-fetch
    @echo "Upstream commits not in HEAD:"
    @git log --oneline HEAD..{{upstream_branch}} || true
    @echo
    @echo "Your commits not in upstream:"
    @git log --oneline {{upstream_branch}}..HEAD || true

# Show the diff of incoming upstream changes
upstream-diff: upstream-fetch
    git diff HEAD...{{upstream_branch}}

# Merge upstream into the current branch
upstream-merge: upstream-fetch
    git merge {{upstream_branch}}

# Merge upstream, then push to your fork
upstream-sync: upstream-merge
    git push origin HEAD

# Cherry-pick specific upstream commits: just upstream-pick <sha>...
upstream-pick +shas: upstream-fetch
    git cherry-pick {{shas}}
