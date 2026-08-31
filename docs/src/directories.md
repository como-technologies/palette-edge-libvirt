# The tooling directories

The checkout holds the source only. Every file that you want to keep lives in
one of four directories in your home directory. Delete the checkout and your
projects, your tokens, your cluster state, and your downloaded image stay.

To see the effective paths, run `just config`.

## The four directories

```bash
{{#include ../../scripts/lib.sh:dirs}}
```

The tooling follows the XDG Base Directory specification, so `XDG_CONFIG_HOME`,
`XDG_DATA_HOME`, `XDG_STATE_HOME`, and `XDG_CACHE_HOME` move all four.

| Directory | Default | Holds |
| --- | --- | --- |
| Configuration | `~/.config/palette-edge-libvirt` | The API key, one environment file for each project, and the link that selects the default project. |
| Data | `~/.local/share/palette-edge-libvirt` | The seed ISO files, the build directory, and the storage pool of a session lab. |
| State | `~/.local/state/palette-edge-libvirt` | The OpenTofu state of the cluster layer, one directory for each project. |
| Cache | `~/.cache/palette-edge-libvirt` | The Ubuntu cloud image, and the release archives of OpenTofu, kubectl, and the GitHub Actions runner. A download replaces any of them. |

`just tofu-install` puts the OpenTofu binary in `~/.local/bin`, which is a fifth
directory. `PEL_BIN_DIR` moves it.

## One state directory for each project

```bash
{{#include ../../scripts/lib.sh:projectstate}}
```

The state is the only record that connects the cluster in Palette to this
checkout, so it gets a directory of its own and never a place in the checkout.
It also holds the administrator kubeconfig of the cluster, so the directory is
mode 0700 and the state file is mode 0600.

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

These variables move the directories. Set them in your shell:

```bash
{{#include ../../templates/project.env:dirs}}
```
