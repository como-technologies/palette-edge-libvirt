# Project rules

These rules apply to every change in this repository. The `justfile` holds the
same list at the top of the file:

```just
{{#include ../../justfile:rules}}
```

## 1. Every action is a recipe

Do not run a command by hand. Do not click a button in a web interface when a
command can do the same task. If you must do a new task, add a recipe first.
Then run the recipe.

A manual step is not repeatable. A result from a manual step does not prove that
the combination works.

## 2. Every create recipe has a remove recipe

Each recipe that makes an object has a partner recipe that removes the object.
The partner recipes in this repository are:

| Create | Remove |
| --- | --- |
| `just host-setup` | `just host-setup-undo` |
| `just net-up` | `just net-down` |
| `just pool-up` | `just pool-down` |
| `just infra-up` | `just infra-down` |
| `just iso-fetch` | `just iso-clean` |
| `just seed NAME` | `just seed-clean` |
| `just host-up NAME` | `just host-down NAME` |
| `just cluster-up` | `just cluster-down` |
| `just docs` | `just docs-clean` |
| `just docs-theme` | `just docs-theme-clean` |

`just nuke` runs the remove recipes together.

## 3. Every recipe is safe to run two or more times

A recipe tests the state before it makes a change. If the object exists, the
recipe prints a skip message and returns success. A second run of `just
cluster-up` makes no new virtual machines.

The scripts use the `skip` function from `scripts/lib.sh` for this message.

## 4. Every recipe has a documentation comment

`just` shows the comment above a recipe as the help text. Run `just` to see the
list. A recipe without a comment has no help text.

## 5. The documentation includes the source

This book does not hold a copy of any code. Each example uses the mdBook
include directive to read the real file. Put an anchor in the source file:

```bash
# ANCHOR: name
echo "the lines to show"
# ANCHOR_END: name
```

Then reference the anchor from a page in `docs/src/`:

```text
\{{#include ../../path/to/file:name}}
```

`just lint` builds the book. A broken path or a missing anchor stops the build.
