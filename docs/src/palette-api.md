# The Palette API

These recipes read your tenant. They change nothing.

| Recipe | Answer |
| --- | --- |
| `just palette-projects` | Each project, and if `PALETTE_PROJECT` names one. |
| `just palette-hosts` | Each host that registered, with its state and its health. |
| `just palette-tokens` | Each registration token, and the project that it registers into. |
| `just palette-clusters` | Each cluster: the uid, the API endpoint, the profiles, the console. |
| `just palette-profiles` | Each cluster profile of the project. |
| `just palette-packs <pack> [version]` | The versions of one pack, or the values of one version. |

Each recipe takes approximately one second. Run `just palette-projects` before
you examine a registration failure. An incorrect `PALETTE_PROJECT` value causes
no error message. The host installs the agent correctly, and it does not show in
the console.

`scripts/palette-lib.sh` holds the requests. `scripts/palette-api.sh` holds the
reports.

## The project is the scope, and the header gives it

A request that names no project cannot see a project object. Put the uid in the
`ProjectUid` header. If the header is absent, Palette reports a permission
error:

```text
Operation 'clusterProfile.delete' is forbidden.
Verify the user has 'clusterProfile.delete' permission
```

The key has that permission. The request named no project. Do not change a role
in the console.

`GET v1/clusterprofiles` with no header returns zero items for the same reason.

The header also makes a delete operation safe. A request that names one project
cannot touch an object of a different project. Thus `just remove-project` cannot
delete the cluster profile of a different project.

This behaviour is confirmed for clusters: the header with one project returns
the clusters of that project, the header with a different project returns none,
and no header returns none. Thus each cluster in `just palette-clusters` is a
cluster of that project.

## A cluster has no health value

`status.health` is `null` on `v1/spectroclusters`, on
`v1/spectroclusters/{uid}`, and on the dashboard metadata endpoint. A health
column shows `-` for each cluster, and gives no information.

`status.conditions` holds the correct data. Each condition has `status: "True"`,
or it does not. A correct edge cluster shows **8 of 8**:

```text
==> clusters in project thelio-lab
  thelio-lab           Running        8 of 8 condition(s) true
```

An edge **host** does have a health value. Thus `just palette-hosts` shows one.

## Palette keeps a deleted cluster in the list

`v1/spectroclusters` returns a deleted cluster permanently, with
`status.state == "Deleted"`. Thus a count of all items never becomes zero.

This causes a failure. `just infra-down` refuses while the project holds a
cluster. A count of all items made that recipe refuse permanently after a
correct `just cluster-down`.

`cluster_count` counts only the clusters that are not deleted. All readers use
this function:

```bash
{{#include ../../scripts/palette-lib.sh:clustercount}}
```

A cluster in the `Deleting` state is included in the count. This is correct.
Such a cluster still holds its cluster profiles. `just cluster-down` waits until
the count becomes zero, and then it removes the profiles.

## The answer gives the console address

`metadata.annotations.rootDomain` names the console of the tenant. A dedicated
instance sets this field to its own name. Do not put `console.spectrocloud.com`
in a script. `just palette-clusters` builds the link from this field.

## A profile has its type on `spec.published`

There is no `spec.type` field. A column that reads that field shows `-` for each
profile. `spec.published` holds `type` (`cluster` or `add-on`), `cloudType`, and
`packs`.

## The packs filter has no space adjacent to AND

```text
filters=spec.name=edge-k8sANDspec.cloudTypes=edge-native
```

Use URL encoding, and use no space on each side of `AND`. `spec.cloudTypes`
matches in the array. `spec.cloudType`, in the singular form, returns zero items
and gives no error.

**Do not filter an add-on pack by cloud.** An add-on pack has no cloud:
`spectro-k8s-dashboard` has the cloud type `all`. An initial version of
`just palette-packs` added the cloud to the filter. That recipe then reported
that each add-on pack was absent from a registry that holds it. The recipe now
names only the pack. The layer and the cloud are columns. Thus a pack of a
different cloud shows an incorrect word, and not an absence.

Add a version to see the default values of that version:

```bash
just palette-packs edge-k8s            # the versions, and the state of each one
just palette-packs edge-k8s 1.33.13    # the default values of one version
```

Run the second command before you copy pack values, or before you replace a line
of them. See [The cluster profile](./cluster-profile.md).

## The uid of an edge host is its name

For an agent-mode edge host, `metadata.uid` is equal to `metadata.name`. The
seed sets `stylus.site.name`, and this causes that result. There are two
effects:

- `just ls` and the Palette host list show the same names.
- `terraform/cluster.tf` needs no table of uid values. It reads one
  `data "spectrocloud_appliance"` for each name in the topology. The read
  operation also confirms that the host registered.

## A LIST request can become a POST request

In 2026-09 the tenant stopped answering a GET request on two paths. The
recipes read both paths in each run:

```text
{"code":405,"message":"method GET is not allowed, but [POST] are"}
```

| Before | Now |
| --- | --- |
| `GET v1/projects?limit=100` | `POST v1/dashboard/projects` |
| `GET v1/edgehosts?limit=100` | `POST v1/dashboard/edgehosts/search` |

Each path takes `{"filter":{},"sort":[]}`. Each path answers with the same
`items` and the same fields. Only the method changed.

The create operation continued to operate, and this made the failure difficult
to find. `POST v1/projects` still made a project. Thus `just new-project` made a
project and then could not read it. `just nuke` read an absent project and left
it in the tenant. The e2e job made an unwanted project in each run, and then
reported that the tenant was empty.

Each endpoint is now in one function only. There were four copies of the
projects request and seven copies of the hosts request. Thus one change to the
API needed eleven corrections:

```bash
{{#include ../../scripts/palette-lib.sh:projectlist}}
```

`token_list` holds the token endpoint for the same reason.

The limits are necessary. `v1/dashboard/edgehosts/search` refuses a limit of
more than 50:

```text
{"code":608,"message":"limit in query should be less than or equal to 50"}
```

`v1/dashboard/projects` accepts 100 and returns 50 items maximum. It gives no
message.

**If a reader function stops operating, examine the method first:**

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X GET \
  -H "ApiKey: $key" "https://api.spectrocloud.com/v1/edgehosts?limit=50"
```

See [A recipe reports "method GET is not
allowed"](./troubleshooting.md#a-recipe-reports-method-get-is-not-allowed).

## `palette-clusters` and `cluster-show` answer different questions

`just cluster-show` reads the OpenTofu state. Thus it answers only for a cluster
that this checkout built. It gives no answer after you remove the state.

`just palette-clusters` reads the API. Thus it answers for each cluster of the
project. Use it to find a cluster that an unsuccessful run left in the tenant.

## The key is in a header

The `api` function puts the key in the `ApiKey` header. The key does not go in a
URL, in a message, or in a log.

If the request fails, the function prints the Palette message and then stops. An
initial version returned the body to the caller. A caller that discarded the
standard output also discarded the cause of the failure.
