#!/bin/bash
set -xe

OLD_BRANCH=$1
CURRENT_BRANCH=$(git branch --show-current)
OLD_REPO="git@github.com:cloudbase\/BMK.git"
CURRENT_REPO="git@github.com:ader1990\/BMK.git"

sed -i "s/${OLD_BRANCH}/${CURRENT_BRANCH}/g" applications/workload/templates/*
sed -i "s/${OLD_BRANCH}/${CURRENT_BRANCH}/g" applications/management/templates/*

sed -i "s/${OLD_REPO}/${CURRENT_REPO}/g" applications/workload/templates/*
sed -i "s/${OLD_REPO}/${CURRENT_REPO}/g" applications/management/templates/*
