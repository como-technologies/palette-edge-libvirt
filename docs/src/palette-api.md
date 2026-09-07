# The Palette API

Six recipes read your tenant and change nothing:

| Recipe | Answer |
| --- | --- |
| `just palette-projects` | every project, and whether `PALETTE_PROJECT` names one |
| `just palette-hosts` | every host that registered, with its state and its health |
| `just palette-tokens` | every registration token, and the project each one registers into |
| `just palette-clusters` | every cluster: the uid, the API endpoint, the profiles, the console |
| `just palette-profiles` | every cluster profile of the project, whatever made it |
| `just palette-packs <pack> [version]` | the versions of one pack, or the values of one version |

Each one costs a second. Run `just palette-projects` before you debug anything
about registration: a wrong `PALETTE_PROJECT` gives no error anywhere, and it is
the most expensive mistake in this tooling.

`scripts/palette-lib.sh` holds the requests, and `scripts/palette-api.sh` holds
the reports.

## The project is the scope, and the header carries it

A project object is invisible to a request that names no project. The uid goes
in the `ProjectUid` header, and Palette reports its absence as a **permission**:

```text
Operation 'clusterProfile.delete' is forbidden.
Verify the user has 'clusterProfile.delete' permission
```

The key holds that permission. Read the message as "which project?", not as a
role to change in the console. `GET v1/clusterprofiles` with no header returns
zero items in the same way.

The header also makes a delete safe. A request that names one project cannot
reach an object of another, so `just remove-project` can never delete the
cluster profile of a project that it is not removing.

This is verified for clusters as well: the header with one project returns that
project's clusters, the header with another returns none, and no header returns
none. So a surprising name in `just palette-clusters` is a cluster that really
is in the project.

## A cluster carries no health

`status.health` is `null` on `v1/spectroclusters`, on
`v1/spectroclusters/{uid}`, and on the dashboard metadata endpoint. A health
column therefore printed `-` for a cluster in good order and told nobody
anything.

`status.conditions` is the real signal. Each condition holds `status: "True"`
or it does not, and a healthy edge cluster shows **8 of 8**:

```text
==> clusters in project thelio-lab
  thelio-lab           Running        8 of 8 condition(s) true
```

An edge **host** does carry health, so `just palette-hosts` is right to print
one.

## Palette keeps a cluster that it deleted

`v1/spectroclusters` returns a deleted cluster for ever, with
`status.state == "Deleted"`. A count of every item therefore never returns to
zero. That is not a curiosity: `just infra-down` refuses while the project holds
a cluster, and counting the list raw made it refuse permanently after a correct
`just cluster-down`.

`cluster_count` counts the live ones, and every reader goes through it:

```bash
{{#include ../../scripts/palette-lib.sh:clustercount}}
```

A cluster in `Deleting` still counts, and that is deliberate. Such a cluster
still holds its cluster profiles, so `just cluster-down` waits for this number
to reach zero before it removes them.

## The console address is in the answer

`metadata.annotations.rootDomain` names the console of the tenant. A dedicated
instance sets it to its own name, so never write `console.spectrocloud.com` into
a script. `just palette-clusters` prints the link it builds from that field.

## A profile carries its type on `spec.published`

There is no `spec.type`. A column that reads one prints `-` for every profile.
`spec.published` holds `type` (`cluster` or `add-on`), `cloudType`, and `packs`.

## The packs filter has no spaces

```text
filters=spec.name=edge-k8sANDspec.cloudTypes=edge-native
```

URL-encoded, and with no space on either side of `AND`. `spec.cloudTypes`
matches inside the array; `spec.cloudType`, singular, silently returns zero
items.

**Never filter an add-on pack by cloud.** An add-on belongs to no cloud:
`spectro-k8s-dashboard` carries the cloud type `all`. `just palette-packs` used
to add the cloud to the filter, and it then reported every add-on pack as absent
from a registry that holds it. The recipe names the pack only, and the layer and
the cloud are columns, so a wrong-cloud pack shows the wrong word instead of
nothing at all.

With a version, the recipe prints the default values of that version:

```bash
just palette-packs edge-k8s            # the versions, and the state of each
just palette-packs edge-k8s 1.33.13    # the default values of one version
```

Run the second before you vendor pack values or replace a line of them. See
[The cluster profile](./cluster-profile.md).

## The uid of an edge host is its name

`metadata.uid == metadata.name` for an agent-mode edge host, because the seed
sets `stylus.site.name`. Two things follow:

- `just ls` and the Palette host list line up, name for name.
- `terraform/cluster.tf` needs no lookup table. It reads one
  `data "spectrocloud_appliance"` for each topology name, and the read itself
  proves that the host registered.

## A LIST can become a POST, and the create keeps working

In 2026-09 the tenant stopped answering a GET on two paths that this repository
reads on every run:

```text
{"code":405,"message":"method GET is not allowed, but [POST] are"}
```

| Was | Is now |
| --- | --- |
| `GET v1/projects?limit=100` | `POST v1/dashboard/projects` |
| `GET v1/edgehosts?limit=100` | `POST v1/dashboard/edgehosts/search` |

Both take `{"filter":{},"sort":[]}` and answer with the same `items` and the
same fields, so only the call changed.

**The half that still worked is what made this expensive.** `POST v1/projects`
still created a project, so `just new-project` made one and then could not read
it back, and `just nuke` read an absent project and left it in the tenant. A
nightly job orphaned a project each time and reported that the tenant was empty.

Each endpoint therefore lives in exactly one function. There were four copies of
the projects call and seven of the hosts call, and that is why one change had to
be made in eleven places:

```bash
{{#include ../../scripts/palette-lib.sh:projectlist}}
```

`token_list` holds the token endpoint for the same reason, before Palette
teaches the lesson a second time.

The limits are not preferences. `v1/dashboard/edgehosts/search` refuses a limit
over 50:

```text
{"code":608,"message":"limit in query should be less than or equal to 50"}
```

`v1/dashboard/projects` accepts 100 and caps the answer at 50 with no message.

**When a reader stops working, test the method before anything else:**

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X GET \
  -H "ApiKey: $key" "https://api.spectrocloud.com/v1/edgehosts?limit=50"
```

See [A recipe reports "method GET is not
allowed"](./troubleshooting.md#a-recipe-reports-method-get-is-not-allowed).

## `palette-clusters` and `cluster-show` answer different questions

`just cluster-show` reads the OpenTofu state, so it answers only for a cluster
that this checkout built, and it says nothing once the state is gone.

`just palette-clusters` reads the API, so it answers for any cluster of the
project, whatever made it. Use it to find a cluster that a failed run left
behind.

## The key is a header, never a URL

`api()` puts the key in the `ApiKey` header. It reaches no URL, no message, and
no log. On an HTTP error the function prints what Palette said and stops, because
an earlier version returned the body to the caller and a caller that discarded
the standard output lost the reason for the failure.
