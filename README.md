# Docker Image 'jfandy1982/find-duplicates'

[![CI/CD Pipeline](https://github.com/jfandy1982/find-duplicates/actions/workflows/continuous_integration_and_deployment.yml/badge.svg?branch=main&event=push)](https://github.com/jfandy1982/find-duplicates/actions/workflows/continuous_integration_and_deployment.yml) [![Docker Image Size](https://img.shields.io/docker/image-size/jfandy1982/find-duplicates/latest)](https://hub.docker.com/repository/docker/jfandy1982/find-duplicates)

Throughout the years, there will be more and more files stored on a NAS. In emergency cases, a 'backup' has to happen as quick as possible, so files are simply copied into a target folder outside of regular backup strategies.

There is a linux tool called 'fdupes' available, which can help to identify duplicates or empty folders or broken symlinks and so on. On a huge data set, the runtime is very long. This container image wrapping this 'fdupes'-command might help, so that the processing can be moved on a NAS (or similar) server. This docker image searches for potential file duplicates and generates result files listing all identified duplicates.

The generated result file containing the file duplicates has the predefined structure created by the 'fdupes' tool.

```txt
42 bytes each:
/volume1/folder1/file1.ext
/volume1/folder42/file0815.ext
...
```

TBD: Describe the docker call.... or refer to the docker.md file in the docker repository... there the different call options may also be described. but then the reference to this local config description is missing.. :(

Oder wir machen hier nur das Repo selbst - und wie man damit lokal umgehen kann. Und ansonsten ist alles bei dockerhub beschrieben, was auch zum docker image gehört... und dessen Konfiguration

- up to 10 data folders, the result folder, the config folder

_Remark:_ This docker image will **NEVER** enable the support for deleting identified file duplicates although the 'fdupes' tool supports that.

# Configuration options

TBD: Add description for the config files

include-pattern; exclude_pattern; path_mappings; MAX_SIZE, BATCH_SIZE variables

# Local development

For local development, the folders need to be prepared manually. Depending on the OS, the scripts needs to be started differently. On LinuxMint for example, you navigate into the scripts folder and start the evaluation by this command

```bash
bash ./findduplicates.sh
```
