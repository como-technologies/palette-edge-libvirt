# Project rules

These rules apply to every change in this repository. The `justfile` holds the
same list at the top of the file:

```just
{{#include ../../justfile:rules}}
```

This page explains each rule. It holds no list of recipes. Run `just` to see the
recipes, and see [Recipes](./recipes.md) for the naming pattern.

## 1. Every action is a recipe

Do not run a command by hand. Do not click a button in a web interface when a
command can do the same task. If you must do a new task, add a recipe first.
Then run the recipe.

A manual step is not repeatable. A result from a manual step does not prove that
the combination works.

## 2. Every create recipe has a remove recipe

Each recipe that makes an object has a partner recipe that removes the object.

`just lint` tests this rule, so the pairs cannot go out of date.
`scripts/lint-pairs.sh` holds the one record of them:

```bash
{{#include ../../scripts/lint-pairs.sh:pairs}}
```

The script makes two tests. Both halves of each pair must exist as a recipe. And
each recipe with the shape of a create recipe must appear in that list, so a new
`x-up` with no `x-down` stops the build.

`just nuke` runs the remove recipes together.

## 3. Every recipe is safe to run two or more times

A recipe tests the state before it makes a change. If the object exists, the
recipe reports a skip and returns success. A second run of `just infra-up`
makes no new virtual machines.

The scripts use the `skip` function from `scripts/lib.sh`:

```bash
{{#include ../../scripts/lib.sh:skip}}
```

## 4. Every recipe has a documentation comment

`just` shows the comment above a recipe as the help text. Run `just` to see the
list. A recipe without a comment has no help text.

## 5. The documentation includes the source

This book holds no copy of any code. Each example uses the mdBook include
directive to read the real file. Put an anchor in the source file:

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

A table of recipes in this book is a maintenance trap. The table looks correct
on the day you write it, and a later rename makes it wrong with no warning. Put
the list in the source, put an anchor around it, and include it. Then one change
corrects both.
