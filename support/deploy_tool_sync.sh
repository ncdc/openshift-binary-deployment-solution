#!/bin/bash -e

for f in ~/.env/*; do
  . $f
done

if [ ! -d $OPENSHIFT_HOMEDIR/app-root/runtime/user/deployments ]; then
  # clean exit if deployments dir doesn't exist
  exit 0
fi

deployment=`ls $OPENSHIFT_HOMEDIR/app-root/runtime/user/deployments | sort | tail -1`

# remove the trailing /
REPO_DIR=${OPENSHIFT_REPO_DIR%?}

# if repo is not a symlink and we have at least 1 deployment, set up the symlink
if [ ! -L $REPO_DIR ] && [ -n $deployment  ]; then
  mv $REPO_DIR $OPENSHIFT_HOMEDIR/app-root/runtime/repo.orig
  ln -s $OPENSHIFT_HOMEDIR/app-root/runtime/user/deployments/$deployment/repo $REPO_DIR
fi
