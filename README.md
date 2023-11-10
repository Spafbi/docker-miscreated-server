# Miscreated Docker Server
The new version of the Miscreated Docker server scripting. Enjoy!

# Requirements
* Linux
* Docker
* bash

This was tested on Ubuntu 22.04 LTS. Your mileage may vary when using other versions of Linux.

# Using this scripting

## Build the server image
```bash
bash ./build-image.sh
```
This only needs to be performed one time per host. This one image will be used by all of the Docker Miscreated servers which are started using this scripting.

## Launch the server
```bash
bash ./launch-server.sh
```
That will launch a Miscreated server container named "miscreated_server" and the server will listen on 0.0.0.0:64090-64093/udp and 0.0.0.0:64094/tcp. Predefined values for some `hosting.cfg` settings are created when the script is executed; see the *_Changing defaults_* section below.

### Defining IP, ports, and container names
You can also specify the following arguments to the above `launch-server.sh` command:
```bash
bash ./launch-server.sh -c my_miscreated_server -i 192.168.1.2 -p 30000
```
`-c` is the container name of the server.
`-i` is the local IP address you want the server's ports to be bound.
`-p` is the starting port for the server. `30000` will use ports `30000-30003/udp` and `30004/tcp`

If you attempt to launch an instance and use the same container name as another Docker container, the already running container will be stopped ***and*** removed. A ***working*** directory based on an alphanumeric version of the defined container name is created in the script directory and will contain a set of default files for the server. Because this directory is based on the container name, this allows you to use the script for launching multiple Miscreated servers, at least as long as you use unique container names for each container instance. It should be noted that *any files and/or directories you create in the working directory will also be automatically mapped to the container*.

#### Working directory examples
If a container name **is not** defined by use of the `-c` option, the container will be named `miscreated_server` and the *working* directory will be created as `miscreatedserver`. If a container name **is** defined by use of the `-c` option, and using `miscreated_pve` as the defined container name for this example, the *working* directory in this case will be created as `miscreatedpve`.

## Stopping the server
You can stop the container manually by executing `docker stop <container_name>` like so: `docker stop miscreated_server`. This *does not* gracefully stop the server.

To gracefully stop a Docker Miscreated server, edit the `<working>/env` file and change `RUN_SERVER=1` to `RUN_SERVER=0`, then send a shutdown command to the server using RCON. Once the server has shut down you can execute the docker stop command without risk of data loss.

## Restarting the server
The Docker containers created by this script should automatically restart if the host is restarted for any reason. If you manually stop the Miscreated server using the `docker stop <container_name>` command, you may start it again by executing `docker start <container_name>`. If you have need to force restart a container you may do so by executing `docker restart <container_name>`

## Changing defaults
After the initial launch of the server you can then edit defaults which are set in `<working>/env` and `<working>/hosting.cfg`. Again, any files and/or directories you create in the working directory will also be automatically mapped to the container. Be careful to not put files or directories in here which may collide with a typical Miscreated installation as the working directory files will take precedence. It is suggested the container be restarted (`docker restart <container_name>`) after making changes to these files.

## Interacting with the container
You can connect to the container interactively by executing `docker exec -it <container_name> /bin/bash`. This will give you a bash prompt where you will be able to watch the server.log file or do any other poking around you want to do. You can use view (`view server.log`) to see a snapshot of the file's contents when you open it. You can also use tail (`tail -n100 -f server.log`) to view the last 100 lines, plus any new lines which get appended. Anything in the container which was not in the working directory prior to the container being starting will be removed when the container is restarted.

## Backups
Once you stop a server, making a backup of the working directory will contain everything needed to restore or move the Miscreated server to a new host if the need arises.

# Eratta
The base Docker container image used to build this image has the ability to use RDP as an interactive desktop. As such, the RDP port (3389) is exposed (you'll see it listed in `docker ps`), but this scripting does not publish this port as it cannot be used with background processes such as the Miscreated server.