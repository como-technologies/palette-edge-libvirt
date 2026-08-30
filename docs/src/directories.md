# The lab directories

The checkout holds the source only. Every file that you want to keep lives in
one of three directories in your home directory. Delete the checkout and your
projects, your tokens, and your downloaded image stay.

To see the effective paths, run `just config`.

## The three directories

```bash
{{#include ../../scripts/lib.sh:dirs}}
```

The lab follows the XDG Base Directory specification, so `XDG_CONFIG_HOME`,
`XDG_DATA_HOME`, and `XDG_CACHE_HOME` move all three.

| Directory | Default | Holds |
| --- | --- | --- |
| Configuration | `~/.config/palette-edge-libvirt` | The API key, one environment file for each project, and the link that selects the default project. |
| Data | `~/.local/share/palette-edge-libvirt` | The seed ISO files and the build directory. |
| Cache | `~/.cache/palette-edge-libvirt` | The Ubuntu cloud image. A download replaces it. |

## The one file in the checkout

`.env` in the checkout is a symbolic link. It holds no value:

```text
<checkout>/.env  ->  ~/.config/palette-edge-libvirt/env  ->  envs/<project>.env
```

`set dotenv-path` in the justfile reads `.env`, and that setting takes a
constant. A constant cannot name your home directory, so the link supplies the
path. The second link holds the choice of project, and it is outside the
checkout. `just default-project <project>` makes both links.

An absent or a broken `.env` loads nothing and reports no error. The recipes
then run on the justfile defaults. `just config` and `just projects` report
this, and name the recipe that corrects it.

## Move a directory

Three variables move the directories. Set them in your shell:

```bash
{{#include ../../.env.example:dirs}}
```
