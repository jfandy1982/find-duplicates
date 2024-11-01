# Docker Image 'jfandy1982/find-duplicates'

[![GitHub](https://img.shields.io/github/license/jfandy1982/find-duplicates?logo=GitHub)](https://github.com/jfandy1982/find-duplicates/blob/main/LICENSE.md)
[![CI/CD Pipeline](https://github.com/jfandy1982/find-duplicates/actions/workflows/continous_integration_and_deployment.yml/badge.svg?branch=main&event=push)](https://github.com/jfandy1982/find-duplicates/actions/workflows/continous_integration_and_deployment.yml)
[![Docker Image Size](https://img.shields.io/docker/image-size/jfandy1982/find-duplicates/latest)](https://hub.docker.com/repository/docker/jfandy1982/find-duplicates)

Throughout the years, there will be more and more files stored on a NAS. In emergency cases, a 'backup' has to happen as quick as possible, so files are simply copied into a target folder outside of regular backup strategies.

There is a linux tool called 'fdupes' available, which can help to identify duplicates or empty folders or broken symlinks and so on. On a huge data set, the runtime is very long. This container image wrapping this 'fdupes'-command might help, so that the processing can be moved on a NAS (or similar) server.
