#!/bin/bash
image_name=spafbi/docker-miscreated-server:latest
docker pull ${image_name}
source $(dirname ${0})/common.sh
