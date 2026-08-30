# Configure the tenant

Two commands configure the lab.

## 1. Store the API key

```bash
just api-key-set
```

The recipe reads the key without an echo. It writes one file outside the
checkout, so no project recipe can delete it. Palette shows the key at
**User Menu** > **My API Keys**.

Do this one time for the workstation.

## 2. Make the project

```bash
just new-project <project>
```

The recipe makes the project in your tenant, makes a registration token for
that project, writes `envs/<project>.env`, and points `.env` at that file.

Do this one time for each lab.

## 3. Confirm the result

```bash
just config
```

The recipe prints the length of the token, never its value.

There is nothing else to fill in. Continue to
[Create the lab](./quickstart.md).

## To change a value

`just new-project` writes a good value for every setting. To change the number
of nodes, the size of a node, the Ubuntu release, or the network, edit
`envs/<project>.env`. [Settings](./settings.md) describes each value.
