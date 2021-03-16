#!/bin/bash

TEST_NAME=$1
SERVER=$2

ivyc target=test ${TEST_NAME}.ivy

cd test

python test.py iters=10 server=${SERVER} stats=true test=${TEST_NAME}

sudo cp -R temp/0/* /results
