OpenShift Binary Deployment Solution
====================================
This is an external solution to allow deploying binary artifacts to OpenShift applications without the need to use git. It consists of a single command line script called "deploy" that performs the following actions:

## Prepare
Downloads the binary artifact from an external location and prepares it for deployment using this tooling. The prepare action invokes a script called `user_prepare` that is responsible for downloading the artifact to a temporary location (e.g. /tmp/somefile.tgz) and reporting the file's location and sha1 checksum back to the prepare action.

Currently, `user_prepare` must be colocated with the scripts in the gear directory. A sample user_prepare script is provided.

When this action finishes, it returns the sha1 checksum to the user, who must then use that to identify which artifact to distribute and activate.

## Distribute
Distributes the binary artifact to all child gears.

## Activate
Activates (deploys) the binary artifact to the head gear and all child gears. Deployments using this process are placed in

`app-root/runtime/deployments/[datetime]`

The existing app-root/runtime/repo directory is moved aside and is now a symlink to `app-root/runtime/deployments/[datetime]/repo`.