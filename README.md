# foundry
Foundry for custom container images — forged here, assembled by Fabricator

## Images

Each image lives in its own top-level folder containing a `Dockerfile`, a `VERSION` and a
`CHANGES.md`:

| Folder | Image |
| --- | --- |
| `arc-runner` | `docker.io/sondn98/arc-runner` |
| `enterprise-gateway` | `docker.io/sondn98/enterprise-gateway` |

## CI/CD

Pull requests against `master` validate and build every image folder they touch but never publish.
Merging to `master` publishes the folders whose `VERSION` changed. Image folders are discovered
automatically — adding one requires no workflow changes.

See **[docs/ci.md](docs/ci.md)** for how to add an image, the tagging policy, and the required
repository secrets.
