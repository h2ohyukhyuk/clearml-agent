#!/bin/bash

sudo docker build . -t clearml-local/torch:2.9.1-py3.12-cu128 -f ./Dockerfile
