## LinuxKit CI

This repository contains the CI configuration for testing [linuxkit/linuxkit][].

It uses the [datakit-ci][] framework.

A public instance of the CI is available at <https://linuxkit.datakit.ci/>.

### Testing locally

1. Run `./test-locally.sh` to build the CI image and start it running.
2. Open the URL displayed in the log output (`APP [datakit-ci] >>> Configure the CI by visiting`)
   in your browser.

After setting a password and logging in as `admin` you should find the CI is building the latest
commit on the master branch.

To use Google Compute for testing:

- Place your key in `local/gcp-key.json`.
- Set the variables in `docker-compose.yml` to your project, zone, etc.
- Place an SSH key that can "ssh root@vm" in `local/builder-ssh/id_rsa`.

### Deploying to production

You need access to the `editions/datakit-ci` swarm, which is controlled by the `editions/datakitciadmins`
team list currently.

If you change `prod.yml`, run `./deploy-prod.sh` to update the deployed services.

If you change the CI service, run `./push.sh` to build the new image, push it to `linuxkitci/ci` and
update the running service to the new version.

When deployed, you should see something like this:

```
[datakit-ci] ~ $ docker stack services linuxkit
ID                  NAME                MODE                REPLICAS            IMAGE                          PORTS
5p9wvbd61huq        linuxkit_bridge     replicated          1/1                 datakit/github-bridge:latest   *:83->83/tcp
jam4zwylni3f        linuxkit_redis      replicated          1/1                 redis:latest
qqhk1va0vc4j        linuxkit_db         replicated          1/1                 datakit/db:latest
ywpmk2g2810j        linuxkit_ci         replicated          1/1                 linuxkitci/ci
```

- `db` is a DataKit database with the state of the system.
- `ci` builds any PRs, branches or tags it finds in the database and writes the status back to it.
- `bridge` monitors GitHub and records anything that needs building in the database, and pushes statuses back.
- `redis` holds HTTP session cookies, so redeploying the CI doesn't log people out.

### Configuring the CI

The main configuration is in `src/ci.ml`, which is quite well commented.

See the [datakit-ci][] documentation for more details.

The main files in this repository are:

- `run-files/gcloud` contains Python scripts used to manage Google Compute build VMs.
- `src` : contains the source code for the CI service.
- `Dockerfile` is a multi-stage build for building the CI service.
- `docker-compose.yml` is a stack for local testing of the CI.
- `prod.yml` is a stack for running the public services on Docker Cloud.

Ideally, the LinuxKit build process should use containers to get any build or test tools needed, without requiring changes to the CI. However, it is possible to add extra software to the CI's `Dockerfile` if necessary.

Note that the production deployment's `docker.sock` is a tunnel to a remote Docker host, not the Docker engine running the CI. This means that directories on the host cannot be bind-mounted into any containers created by the build.

### Security notes

Although this repository is public, the software in it runs with access to various signing keys, etc.
If a malicious PR to this repository is accepted, an attacker will be able to steal the keys.

For the [linuxkit/linuxkit][] repository itself:

- PRs are tested in VMs with no privileges, BUT
- For branches and tags, the `Makefile` is run directly in the context of the CI, with access to all its keys.
  This means that if a malicious LinuxKit PR is accepted, the attacker will also be able to steal the CI keys.

It might be better from a security perspective to sandbox all builds, and have the CI itself (not LinuxKit's Makefile) handling signing and uploading. However, there is also a desire to keep this independent of any particular CI system. Also, testing on various platforms requires deploying images using the `linuxkit` tool, so this needs to have the keys.

In any case, when updating the CI configuration DO NOT execute any code from PRs (which can be submitted by anyone) in any non-sandboxed environment. In particular, when testing PRs using the `linuxkit` tool, DO NOT use the version of the tool from the PR.


[datakit-ci]: https://github.com/moby/datakit/tree/master/ci
[linuxkit/linuxkit]: https://github.com/linuxkit/linuxkit
