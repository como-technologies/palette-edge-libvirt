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

There is nothing to fill in afterwards. See
[The project layout](./project-layout.md).

## 2. Confirm the result

```bash
just projects   # the projects that have a file, * marks the default
```

`just projects` reads the local files. `just palette-projects` reads your
tenant.

When the new project has the `*`, continue to
[Create the machines](./machines.md).
