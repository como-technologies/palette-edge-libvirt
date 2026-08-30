# Configure the tenant

The workstation needs one credential: your Palette API key.

## 1. Store the API key

```bash
just api-key-set
```

The recipe reads the key without an echo and writes one file outside the
checkout. Palette shows the key at **User Menu** > **My API Keys**.

Do this one time for the workstation. Every project uses the same key.

## 2. Confirm the result

```bash
just api-key-status
just palette-projects
```

The first recipe reports the length of the key, never its value. The second
recipe reads your tenant with that key, so a correct list proves that the key
works.

## Next

See [Create a project](./project.md).

The API key is the only value that you give by hand. `just new-project` writes
every other value. [Settings](./settings.md) describes each one.
