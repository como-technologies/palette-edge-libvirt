# Recipes

The `justfile` is the only interface to this repository. To see every recipe and
its help text, run:

```bash
just
```

**This book holds no list of the recipes.** The output of `just` is always
correct for the checkout that you have. A table here would be correct on the day
someone writes it and wrong after the next rename. See
[project rule 5](./rules.md#5-the-documentation-includes-the-source).

## The naming pattern

| Suffix or prefix | Meaning |
| --- | --- |
| `-up` | Create the object and start it. |
| `-down` | Stop the object and remove it. |
| `-fetch` | Download a file into a cache. |
| `-clean` | Delete generated files. |
| `-status` | Report progress. Makes no change. |
| `-undo` | Reverse a recipe that changes the workstation. |
| `new-` | Create an object in your Palette tenant. |
| `remove-` | Delete an object from your Palette tenant. |

A recipe with no suffix reports information, for example `config`, `ls`, `ip`,
`projects`, and `preflight`.

`scripts/lint-pairs.sh` reads these shapes. A new recipe that creates something
and has no partner stops `just lint`:

```bash
{{#include ../../scripts/lint-pairs.sh:pairs}}
```

## Recipes with arguments

```bash
just new-project iris "A description"
just default-project iris
just host-up pe-wk-3            # role defaults to worker
just host-up pe-cp-2 control    # control plane size
just seed pe-wk-3
just console pe-cp-1
```

## Bash completion

The completion completes the recipe names, and it completes the arguments: the
host names, the roles `control` and `worker`, and the project names.

For the current shell:

```bash
source <(just bash-completion)
```

For every shell, choose one:

```bash
just bash-completion-install          # writes a file for your user
just bash-completion >> ~/.bashrc     # writes the script into your .bashrc
```

`bash-completion-install` prints the path of the file, so this also works:

```bash
source "$(just bash-completion-install)"
```

`just bash-completion-uninstall` removes the installed file.

The completion binds to the `just` command, so bash uses it for every project.
This is safe. It completes the recipe names of any justfile, and it completes
the arguments only in this checkout. In another project the argument completion
gives nothing.

## The layers

The `justfile` holds the configuration and thin recipes. Each recipe with logic
calls a script in `scripts/`, and the recipe passes the values in the
environment. This keeps the `justfile` readable, and it lets `shellcheck` test
the logic.

To see what one script does, read the comment at the top of it. Every script
carries its purpose, its inputs, and a note on how it stays idempotent:

```bash
head -20 scripts/host-up.sh
```

`scripts/lib.sh` holds the shared functions. `scripts/palette-lib.sh` holds the
functions for the Palette API. Both are sourced, never executed.

## Quality

```bash
just fmt    # format the justfile
just lint   # test the format, the pairs, the scripts, and the docs build
```

`just lint` runs four tests:

1. `just --fmt --check` tests the format of the `justfile`.
2. `scripts/lint-pairs.sh` tests
   [project rule 2](./rules.md#2-every-create-recipe-has-a-remove-recipe).
3. `shellcheck` tests every script.
4. `mdbook build` builds the book, which tests every include path and every
   anchor.

The GitHub Actions workflow runs `just lint` on each push and each pull request.
