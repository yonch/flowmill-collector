# Flowmill telemetry collector #

Flowmill telemetry collector is an agent that can collect low level telemetry
straight from the Linux Kernel using the [eBPF technology](https://ebpf.io/).
It does so with negligible overhead towards compute and network resources.

This telemetry is then sent to a pipeline that can enrich it and provide
invaluable insight about you distributed application.

## Building the collector ##

There's a docker build image provided with all dependencies pre-installed,
ready to build the collectors.

Building the collectors images is as simple as running the build image within
docker with the following setup:

```
docker run \
  -it --rm \
  --mount "type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock" \
  --mount "type=bind,source=$(git rev-parse --show-toplevel),destination=/root/src,readonly" \
  --env FLOWMILL_SRC=/root/src \
  --env FLOWMILL_OUT_DIR=/root/out \
  --workdir=/root/out \
  build-env \
    ../build.sh docker
```

The resulting docker image will be placed in the host's docker daemon under the
name `kernel-collector`.

The images can also be automatically pushed to a docker registry after they're built.
By default, they're pushed to a local docker registry at `localhost:5000`. The registry
can be changed by setting the environment variable `FLOWMILL_DOCKER_REGISTRY` in the
build image, as so:

```
docker run \
  -it --rm \
  --mount "type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock" \
  --mount "type=bind,source=$(git rev-parse --show-toplevel),destination=/root/src,readonly" \
  --env FLOWMILL_SRC=/root/src \
  --env FLOWMILL_OUT_DIR=/root/out \
  --env FLOWMILL_DOCKER_REGISTRY="localhost:5000" \
  --workdir=/root/out \
  build-env \
    ../build.sh docker-registry
```

The source code for the build image as well as instructions on how to build it
can be found in its repo [at github.com/Flowmill/flowmill-build-env](
https://github.com/Flowmill/flowmill-build-env).

## Running the collector ##

Running the Flowmill collector should be as easy as running a docker image:

```
docker run -it --rm \
  --env FLOWMILL_INTAKE_PORT="${FLOWMILL_INTAKE_PORT}" \
  --env FLOWMILL_INTAKE_HOST="${FLOWMILL_INTAKE_HOST}" \
  --env FLOWMILL_AUTH_KEY_ID="KFIIHR5SFKS3TQFPZWZK" \
  --env FLOWMILL_AUTH_SECRET="DatfNxs42qP1v8u281G9lyNNmFvWLmehNwVHQ9LT" \
  --env FLOWMILL_INTAKE_NAME="oss" \
  --privileged \
  --pid host \
  --network host \
  --log-console \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --volume /sys/fs/cgroup:/hostfs/sys/fs/cgroup \
  --volume /etc:/var/run/flowmill/host/etc \
  --volume /var/cache:/var/run/flowmill/host/cache \
  --volume /usr/src:/var/run/flowmill/host/usr/src \
  --volume /lib/modules:/var/run/flowmill/host/lib/modules \
  kernel-collector \
    --log-console
```

### Collector settings ###

Environment variables:

- `FLOWMILL_AUTH_KEY_ID`: this is the agent key id used to authenticate with Flowmill
- `FLOWMILL_AUTH_SECRET`: this is the agent secret used to authenticate with Flowmill
- `FLOWMILL_INTAKE_NAME`: this is the name of the Flowmill intake server
- `FLOWMILL_INTAKE_HOST`: this is the hostname or IP address of the Flowmill intake server
- `FLOWMILL_INTAKE_PORT`: this is the port of the Flowmill intake server
- `FLOWMILL_AUTHZ_SERVER`: this is the host:port of Flowmill auth server (default: app.flowmill.com)
- `FLOWMILL_INTAKE_AUTH_METHOD`: this is the auth method to use when connecting to the intake, valid values are "authz" or "none", (default: "authz")

Volumes:

- `/var/run/docker.sock`: enables the collector to talk to the local Docker daemon
- `/sys/fs/cgroup`: allows the collector to read cgroup information
- `/etc`: allows the collector to read package manager settings in order to
  fetch kernel headers in case they're not pre-installed on the host (necessary
  for eBPF - optional if pre-installed kernel headers are available on the host)
- `/var/cache`: cache fetched kernel headers on the host (optional)
- `/usr/src` / `/lib/modules`: allows the collector to use kernel headers
  pre-installed on the host(necessary for eBPF)

Docker settings:

The collector needs privileged access since it uses the eBPF mechanism from the
Linux kernel, therefore these settings need to be passed to docker: `--privileged`,
`--pid host` and `--network host`.

## Integration with OpenTelemetry Collector ##

Flowmill collector can alternatively send telemetry to OpenTelemetry Collector
(otel-col) in the form of Log entries.

### Quick-start for the OpenTelemetry Collector ###

A minimal config is included in `dev/otel-config.yaml`, and it is possible to run 
the standard otel distribution docker image on port 8000 with:
```
docker run -v $PWD/dev/otel-config.yaml:/etc/otel/config.yaml -p 8000:8000 otel/opentelemetry-collector
```
### Configuring otel-col to receive telemetry ###

A few changes need to be made to otel-col's config file. Please refer to 
otel-col's documentation for details on [how to run the
collector](https://opentelemetry.io/docs/collector/getting-started/#docker).

First you need to set up an HTTP endpoint for an OTLP receiver. The example
below binds the receiver to all interfaces (`0.0.0.0`) on port `8000`. For more
information, refer to [otel-col's
documentation](https://opentelemetry.io/docs/collector/configuration/#receivers):
```
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:8000
```

If you need to enable TLS on the endpoint, check [the
documentation](https://github.com/open-telemetry/opentelemetry-collector/blob/main/config/configtls/README.md#server-configuration).

Then make sure the Log Service is also enabled and connected to the OTLP HTTP
receiver. For more information, refer to [otel-col's
documentation](https://opentelemetry.io/docs/collector/configuration/#service):

```
service:
  pipelines:
    logs:
      receivers: [otlp]
      # processors: # TODO: add processors here
      # exporters: # TODO: add exporters here
```

By making sure the Log Service is enabled in otel-col and receiving HTTP
requests in OTLP format, now Flowmill collector is able to send telemetry to
otel-col on port `8000`.

For more information on the OTLP receiver, refer to [otel-col's
documentation](https://github.com/open-telemetry/opentelemetry-collector/blob/main/receiver/otlpreceiver/README.md).

### Configuring Flowmill collector to send telemetry to otel-col ###

The flowmill collector needs to know a few things in order to connect to
otel-col's receiver as its intake. The difference between connecting to the
standard Flowmill intake vs connecting to otel-col's receiver is the intake
encoding. For otel-col's receiver the encoding must be set to `otlp_log`.

Intake settings are controlled by environment variables set on Flowmill
Collector's container (e.g.: can be set with `docker`'s --env command line
argument). Below is a list of settings along with the name of the environment
variable and suggested values for a proof-of-concept (note that these are already 
present in the `docker run` command below):
```
export FLOWMILL_INTAKE_HOST=127.0.0.1    # host
export FLOWMILL_INTAKE_PORT=8000         # port
export FLOWMILL_INTAKE_DISABLE_TLS=true  # TLS
export FLOWMILL_INTAKE_ENCODER=otlp_log  # encoder
export FLOWMILL_INTAKE_NAME=oss          # name for [TLS SNI](https://en.wikipedia.org/wiki/Server_Name_Indication)
```

Here's an example:

```
docker run -it --rm \
  --env FLOWMILL_INTAKE_HOST="127.0.0.1" \
  --env FLOWMILL_INTAKE_PORT="8000" \
  --env FLOWMILL_INTAKE_DISABLE_TLS=true \
  --env FLOWMILL_INTAKE_ENCODER="otlp_log" \
  --env FLOWMILL_INTAKE_NAME="oss" \
  --env FLOWMILL_AUTH_KEY_ID="KFIIHR5SFKS3TQFPZWZK" \
  --env FLOWMILL_AUTH_SECRET="DatfNxs42qP1v8u281G9lyNNmFvWLmehNwVHQ9LT" \
  --privileged \
  --pid host \
  --network host \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --volume /sys/fs/cgroup:/hostfs/sys/fs/cgroup \
  --volume /etc:/var/run/flowmill/host/etc \
  --volume /var/cache:/var/run/flowmill/host/cache \
  --volume /usr/src:/var/run/flowmill/host/usr/src \
  --volume /lib/modules:/var/run/flowmill/host/lib/modules \
  kernel-collector \
    --log-console
```
