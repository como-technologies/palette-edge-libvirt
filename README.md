# palette-edge-libvirt

A local Kubernetes test cluster that runs on one workstation.

It uses Spectro Cloud Palette (Profiles, Packs, and Edge) to create and remove
test Kubernetes clusters on libvirt/KVM virtual machines. You validate a
combination of an operating system, a CNI, a CSI, and add-on packs on virtual
machines first. You commit the combination to real hardware only after the test
passes.

The reference workstation is a System76 Thelio with 32 cores and 128 GB of RAM.

The tooling uses Palette **agent mode**. Each host boots the stock Ubuntu cloud
image, and cloud-init installs the Palette agent. The tooling builds no operating
system image, so it needs no Docker and no CanvOS.

## Quick start

```bash
just host-setup          # install libvirt, KVM, and the helper tools
# restart the workstation for the new group membership
just api-key-set         # store your Palette API key, one time
just new-project pe      # makes the project, its token, and its env file
just preflight           # test the workstation
just infra-up            # network, pool, image, seeds, machines, registration
```

`infra-up` returns when every host is registered, so the next layer is ready.
That layer makes the cluster profile and the cluster in Palette, with
**Palette eXtended Kubernetes - Edge (PXK-E)** for the Kubernetes layer. It has
no recipe yet; Terraform is the plan.

To remove everything on the workstation:

```bash
just nuke
```

## Project rules

1. Every action is a recipe. Do not run commands by hand.
2. Every recipe that creates an object has a recipe that removes it.
3. Every recipe is safe to run two or more times.
4. Every recipe has a documentation comment. The comment is the help text.
5. The documentation includes the source. It does not copy the source.

Run `just` to see every recipe. Run `just config` to see the current settings.

## Bash completion

```bash
source <(just bash-completion)     # this shell
just bash-completion-install       # every shell
```

The completion adds the host names, the roles, and the project names. It is
safe for every project: in another checkout it completes recipe names only.

## Documentation

```bash
just docs-serve   # build the book and open it at http://localhost:3000
```

The source is in `docs/src/`. The book uses mdBook with `mdbook-mermaid` for the
diagrams and `mdbook-gruvbox` for the theme.

## Requirements

| Tool | Function |
| --- | --- |
| `just` | Runs every recipe. |
| `libvirt`, `qemu-kvm`, `virtinst` | Runs the virtual machines. |
| `genisoimage` or `xorriso` | Builds the seed ISO. |
| `mdbook`, `mdbook-mermaid`, `mdbook-gruvbox` | Builds the documentation. |
| `shellcheck` | Tests the shell scripts. |

`just host-setup` installs the system packages. Install the `mdbook` tools with
`cargo install mdbook mdbook-mermaid mdbook-gruvbox`.

## Security

Two credentials, kept apart on purpose:

- The **registration token** is project scoped. `just new-project` makes one for
  each project and writes it into the environment file of that project.
  `just remove-project` deletes it with the project.
- The **API key** is a tenant credential: a key carries every permission of its
  owner, and Palette cannot scope one. It lives in
  `~/.config/palette-edge-libvirt/api-key`, outside the checkout, so no project
  recipe can delete it. Use `just api-key-set`.

The checkout holds the source only. The projects, the seeds, and the cloud
image live in `~/.config`, `~/.local/share`, and `~/.cache`, so `rm -rf` on the
checkout destroys no project. Run `just config` to see the paths.

Run `just host-eject NAME` after a host registers. That recipe removes the seed
ISO from the virtual machine, so the host keeps no copy of the token.

`just config` and `just preflight` print the length of the token, never the
value.
