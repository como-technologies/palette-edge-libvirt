# The project layout

One lab serves one Palette project. The lab keeps one environment file for each
project, and a link selects the default one:

```text
~/.config/palette-edge-libvirt/envs/pe-thelio.env
~/.config/palette-edge-libvirt/envs/iris.env
~/.config/palette-edge-libvirt/env -> envs/pe-thelio.env
```

The files are outside the checkout, so `rm -rf` on the checkout destroys no
project. [The lab directories](./directories.md) describes the layout and the
`.env` link that reaches it.

Each file holds a registration token. The directory has the mode 0700 and each
file has the mode 0600.

For the commands, see [Projects](./projects.md).

## What new-project does

The recipe does four things:

1. It makes the project in your Palette tenant, with the description.
2. It makes a registration token that belongs to that project.
3. It writes the environment file of the project with good values and that
   token.
4. It makes the new project the default.

Step 2 removes the last manual step. Nobody copies a token from the console.
`PALETTE_TOKEN_DAYS` sets the lifetime, and the default is 90 days.

Step 3 chooses values that do not collide with an existing lab:

| Value | How the recipe chooses it |
| --- | --- |
| `PALETTE_PROJECT` | The project name. |
| `LAB_NAME` | The first 12 characters of the name, with a number if that prefix is in use. |
| `LAB_SUBNET` | The first free subnet from 192.168.140 to 192.168.199. |
| `PALETTE_EDGE_TOKEN` | The token from step 2. |

The recipe reads the subnets of the other environment files **and** of the
libvirt networks, so a new project never takes the subnet of a running lab.

Every other value comes from `.env.example`. See [Settings](./settings.md).

## The API key is not in the file

A key carries every permission of the user that owns it, so it is a tenant
credential and not a project one. It lives at
`~/.config/palette-edge-libvirt/api-key`, and no project recipe touches it.
`just remove-project` therefore cannot delete it.

An earlier version wrote a copy of the key into each project file. One project
removal then destroyed a tenant credential, and Palette does not show a key
value again after it makes one.

## What remove-project does

The recipe reverses all four steps: it deletes the registration token, it
deletes the project from the tenant, it deletes the environment file, and it
removes the default link if that link pointed at the removed file.

**The token goes first.** Palette refuses to delete a project while a token
names it as the default project, and the API reports that as an HTTP 500:

```text
Unable to delete the resource as <name> edgetoken(s) in-use
```

The recipe protects you two times:

- It refuses while the project holds a cluster or a host. Delete the cluster in
  Palette, run `just cluster-down`, then deregister the hosts.
- It asks you to type the project name, and it names the token that it deletes
  with the project.

`FORCE=1` answers the question in advance:

```bash
FORCE=1 just remove-project <project>
```

The recipe removes **no** lab object on the workstation. Run `just cluster-down`
first, or the virtual machines stay and their project is gone.

## Adopt a .env that you wrote

A `.env` file that you wrote by hand works where it is. To give it a project
name and move it into the layout:

```bash
just adopt-project <project>
```

The twin makes `.env` a regular file again:

```bash
just unadopt-project
```

## Two labs at the same time

Two projects with a different `LAB_NAME` and a different `LAB_SUBNET` run at the
same time. `new-project` gives both values, so this needs no edit.

The recipes operate on the default project only. Change the default first:

```bash
just default-project iris
just cluster-up
```
