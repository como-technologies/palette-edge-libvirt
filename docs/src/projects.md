# Projects

One lab serves one Palette project. Each project has its own environment file,
and the recipes operate on one project at a time.

## Make a project

```bash
just new-project <project>
just new-project <project> "A description"
```

The recipe makes the project in your tenant, makes a registration token for it,
writes the environment file of the project, and makes that project the
default.

There is nothing to fill in afterwards.

## See and select

```bash
just projects                  # the projects that have a file, * marks the default
just default-project <project> # work on a different project
```

`just projects` reads the local files. `just palette-projects` reads your
tenant.

## Remove a project

```bash
just remove-project <project>
```

The recipe deletes the token, the project, and the file. It asks you to type
the project name first, because a delete is not reversible.

Remove the lab first:

```bash
just cluster-down
just remove-project <project>
```

## More

[The project layout](./project-layout.md) describes the files, the order that
`remove-project` uses, and how to run two labs at the same time.
