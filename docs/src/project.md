# Create a project

One cluster serves one Palette project. Each project has its own environment file,
and the recipes operate on one project at a time.

## 1. Create the project

```bash
just new-project <project>
just new-project <project> "A description"
```

The recipe makes the project in your tenant, makes a registration token for it,
writes the environment file of the project, and makes that project the
default.

There is nothing to fill in afterwards.

## 2. Confirm the result

```bash
just projects   # the projects that have a file, * marks the default
```

`just projects` reads the local files. `just palette-projects` reads your
tenant.

## Next

Create the hosts. See [Create the machines](./machines.md).

## More

[The project layout](./project-layout.md) describes the files, the order that
`remove-project` uses, and how to run two clusters at the same time.
