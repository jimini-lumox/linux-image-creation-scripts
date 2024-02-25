
## Debian Rootfs Creation

```sh
docker build -t debian-os-builder -f docker/Dockerfile docker

# ulimit required to fix an issue in docker container when running fakeroot
docker run --rm -it --ulimit nofile=32768:32768 -v "$PWD":/debian-os-builder debian-os-builder /bin/bash
```
Then in container
```sh
cd /debian-os-builder
./run_build.sh
```
