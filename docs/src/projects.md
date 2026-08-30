# Projects

One lab serves one Palette project. The repository keeps one environment file
for each project, and `.env` is a symbolic link to the file of the default
project.

```text
envs/pe-thelio.env      the environment file of one project
envs/iris.env           the environment file of another project
.env -> envs/pe-thelio.env
```

`set dotenv-load` in the justfile reads `.env`. The link therefore selects the
project that every recipe operates on. Git ignores `.env` and `envs/`, because
both hold your registration token.

## Make a project

```bash
just new-project iris
just new-project iris "The iris application on Palette Edge"
```

The recipe does four things:

1. It creates the project in your Palette tenant, with the description.
2. It creates a registration token that belongs to that project.
3. It writes `envs/iris.env` with good defaults and that token.
4. It points `.env` at the new file, so the new project becomes the default.

Step 2 removes the last manual step. Nobody copies a token from the console.
`PALETTE_TOKEN_DAYS` in `.env` sets the lifetime, and the default is 90 days.

Step 3 gives values that do not collide with an existing lab:

| Value | How the recipe chooses it |
| --- | --- |
| `PALETTE_PROJECT` | The project name. |
| `LAB_NAME` | The first 8 characters of the name, with a number if that prefix is in use. |
| `LAB_SUBNET` | The first free subnet from 192.168.140 to 192.168.199. |
| `PALETTE_API_KEY` | Copied from the current environment. |
| `PALETTE_EDGE_TOKEN` | The token that step 2 makes for this project. |

The recipe reads the subnets of the other environment files **and** of the
libvirt networks. A new project therefore never takes the subnet of a running
lab.

Every other value comes from `.env.example`. Edit `envs/iris.env` to change the
topology for that project.

### The first project

A new checkout has no API key. Give it for the one command. The recipe makes
the registration token, so you need no token:

```bash
PALETTE_API_KEY=... just new-project iris
```

Later projects copy the API key from the current environment.

## Change the default

```bash
just projects                  # list the projects, * marks the default
just default-project pe-thelio # point .env at another project
```

`just projects` reads the local files only. It makes no API call. To read the
tenant, run `just palette-projects`.

## Remove a project

```bash
just remove-project iris
```

This is the twin of `new-project`. It reverses all four steps: it deletes the
registration token, it deletes the project from the tenant, it deletes
`envs/iris.env`, and it removes the `.env` link if that link pointed at the
removed file.

The token goes first. **Palette refuses to delete a project while a token names
it as its default project**, and the API reports that as an HTTP 500 with the
message `Unable to delete the resource as <name> edgetoken(s) in-use`.

The recipe protects you two times:

- It refuses while the project holds a cluster or a host. Delete the cluster in
  Palette, run `just cluster-down`, then deregister the hosts.
- It asks you to type the project name, and it names the token that it deletes
  with the project. A delete is not reversible.

Give `FORCE=1` to answer in advance:

```bash
FORCE=1 just remove-project iris
```

The recipe removes the lab objects on the workstation for **no** project. Run
`just cluster-down` first.

## Adopt an existing .env

A checkout from before the project layout has a regular `.env` file. Move it
into the layout one time:

```bash
just adopt-project pe-thelio
```

The twin makes `.env` a regular file again:

```bash
just unadopt-project
```

## Two labs at the same time

Two projects with a different `LAB_NAME` and a different `LAB_SUBNET` run at the
same time. `new-project` gives both values, so this works with no edit.

The recipes operate on the default project only. To work on the other lab,
change the default first:

```bash
just default-project iris
just cluster-up
```
