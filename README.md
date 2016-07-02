# minecraft-server-docker

### An easy to use Docker container for [Minecraft Server][0]

## Building

Currently this image is automatically built from [Docker Hub][1]

To build locally simply execute: `make build`

# Running

Two parameters are available when running this image:
1. `I_ACCEPT_MINECRAFT_EULA=yes`
   * This option is required on first execution. Basically it just creates the "eula.txt" file.
2. `I_ACCEPT_ORACLE_JAVA_LICENSE=yes`
   * This option indicates that Oracle Java should be used.

There are multiple ways of running the image:
1. Run in foreground
   * `make run [parameters]`
2. Run as background daemon
   * `make start [parameters]`
3. Run interactive bash shell instead of minecraft server
   * `make shell [parameters]`

# Persistent Data

The docker image requires a volume mounted at `/mc_data`. This volume will contain the server configuration files as well as the world and logs folders.

[0]: https://minecraft.net/en/download/server
[1]: https://hub.docker.com/r/skepickle/minecraft-server-docker/

