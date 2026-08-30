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

## The checkout holds no configuration

One link selects the project:

```text
~/.config/palette-edge-libvirt/env  ->  envs/<project>.env
```

`just` gives a setting no function and no tilde, so the justfile can name no
path in your home directory. It can name a command:

```just
set dotenv-command := 'scripts/dotenv.sh'
```

`just` runs that script from the justfile directory, and reads the output as an
environment file. The script computes the path, follows the link, and prints
the file. This is the reason that the checkout holds no configuration file, and
that two checkouts operate on the same project.

`just default-project <project>` makes the link. With no link the script prints
nothing and each recipe uses its default value. `just config` and
`just projects` report this, and name the recipe that corrects it.

## Move a directory

Three variables move the directories. Set them in your shell:

```bash
{{#include ../../templates/project.env:dirs}}
```
