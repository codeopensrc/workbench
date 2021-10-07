#!/bin/bash

CONTAINER_ID=$1
kill -9 $(pgrep -f $CONTAINER_ID)
