# OpenShift Binary Deployment Solution

## Background & Motivation
OpenShift currently only supports deploying updated code for an application via git. When you commit and push code to your application's OpenShift git repository, OpenShift takes care of doing everything necessary to deploy your latest changes.

If you have a scalable application, a `git push` will result in your latest changes being copied to all the gears that make up your application. Features such as rolling deployments and rollback have not yet been implemented in OpenShift, and this tooling attempts to provide these features.

This is an external solution to allow deploying binary artifacts to OpenShift applications without the need to use git. It consists of a single command line script called "deploy" that performs several actions, described below.

But first, some information on binary artifacts and what they are.

## Binary Artifacts
Binary artifacts are compressed tar files (.tar.gz). They contain everything you would expect to see in a normal OpenShift application:

- .openshift directory (including .openshift/actions_hooks/user_prepare, if desired)
- application code

**NOTE**: If your artifact is Java-based, make sure it includes the precompiled/packaged output (e.g. a .war file) in the deployments directory, as this tooling will **NOT** run the build hook.

Prior to executing the commands below, create a binary artifact and upload it to a web server (e.g., for Java-based deployments, deploying your artifacts to a Maven repository server such as Nexus or Artifactory is a good option).

# Usage
## Init
Usage: `deploy init APP`

Initializes the application to be able to use this tooling. This action will copy the supporting scripts to the application's head gear and initialize the gear for binary deployments.

## Prepare
Usage: `deploy prepare APP ARTIFACT_URL`

Downloads a binary artifact from an external location and prepares it for deployment using this tooling. After downloading the artifact, the prepare action extracts .openshift/action_hooks/user_prepare from the artifact and invokes it, if it exists. The `user_prepare` script may perform operations such as downloading environment specific files and incorporating them into the artifact (since typically you want your artifacts to be able to be deployed to development, testing, staging, and production environments without having to make any changes to them).

When this action finishes, it returns the sha1 checksum to the user, who must then use that to identify which artifact to distribute and activate.

## Distribute
Usage: `deploy distribute APP CHECKSUM`

Distributes the binary artifact to all child gears of a scalable application. This action is only necessary for scalable applications that have at least 1 child gear.

## Activate
Usage: `deploy activate APP CHECKSUM [--dry-run] [--gears GEARS]`

Activates (deploys) the binary artifact to some or all of the gears for the application. Deployments using this process are placed in

`app-root/runtime/user/deployments/[datetime]`

The existing `app-root/runtime/repo` directory is moved aside and is now a symlink to `app-root/runtime/user/deployments/[datetime]/repo`.

### Targeting gears
Activations can apply to all of an application's gears (the default behavior), or a subset. To operate on a subset of gears, use the `deploy partition` action to divide the application's gears into multiple sets (see below for details on running that action). Once you have your partition files, you can use the `--gears` option to specify the partition file containing the gears you wish to activate.

### Dry runs
If you want to see if the activation should be able to succeed, without actually performing the activation, you can use the `--dry-run` option to do so.

## Partition
Usage: `deploy partition APP --output-dir OUTPUT_DIR --counts COUNTS`

This will create 1 or more files containing subsets of gears that can be used as input to the activate and rollback actions. A partition file simply contains the SSH urls of the desired gears, one per line.

The files will be named using the following convention: APP-[parition number]-[total number of partitions]. For example, if the application's name is myapp, and there are 3 total partitions, the files would be named

* myapp-1-3
* myapp-2-3
* myapp-3-3

You can specify an `--output-dir` in which all the partition files will be created.

### How to partition
Currently you create partitions by specifying the number of gears you want in each partition, separated by commas. For example:

`--counts 2,3,4` will create 3 partitions. The first partition will have 2 gears in it, the second partition will have 3 gears in it, and the third partition will have 4 gears in it.

If there are still gears left over after assigning gears to the partitions based on the counts specified, a final partition will be created with all the remaining unassigned gears. For example, if you have 10 gears, and you do `--counts 2`, you will get 2 partition files: 1 with 2 gears, and 1 with 8 gears.

## Rollback
Usage: `deploy rollback APP [--dry-run] [--gears GEARS]`

Rolls back to the previously deployed version (if it exists). In order for the rollback action to succeed, you need to have deployed at least 2 versions using this tooling. It will not rollback to the original non-binary deployment.

You can use `--dry-run` to see which gears should roll back successfully.

By default, the rollback command applies to all of an application's gears. You can use the `--gears` option to target specific subsets of gears, as described above.

## Status
Usage: `deploy status APP`

Displays information about all the gears of an application:

* Gear UUID
* SSH URL
* Deployed artifact
* Gear state

Example output:

	$ ./deploy status s2
	Application s2 has 3 gears:
	Gear 51b0dde3a7cfd1abf200006d
	  SSH URL: ssh://51b0dde3a7cfd1abf200006d@s2-agoldstein.example.com
	  Deployed version: myapp-1.0.tar.gz (34e2c81bc295d8b769d9531c44532390d4104705: OK)
	  State: started
	
	Gear 51b0e483a7cfd1abf2000092
	  SSH URL: ssh://51b0e483a7cfd1abf2000092@51b0e483a7cfd1abf2000092-agoldstein.example.com
	  Deployed version: Unknown; deployment not activated using binary deployment process
	  State: stopped
	
	Gear 51b0e665a7cfd1abf20000a5
	  SSH URL: ssh://51b0e665a7cfd1abf20000a5@51b0e665a7cfd1abf20000a5-example.com
	  Deployed version: myapp-1.0.tar.gz (34e2c81bc295d8b769d9531c44532390d4104705: OK)
	  State: started

## Artifacts
Usage: `deploy artifacts APP`

Displays information about the artifacts distributed to all the gears of an application:

* artifact checksum
* artifact name

Example output:

	$ ./deploy artifacts s2
	Gear 51b0dde3a7cfd1abf200006d
	  34e2c81bc295d8b769d9531c44532390d4104705: myapp-1.0.tar.gz
	
	Gear 51b0e483a7cfd1abf2000092
	  34e2c81bc295d8b769d9531c44532390d4104705: myapp-1.0.tar.gz
	
	Gear 51b0e665a7cfd1abf20000a5
	  34e2c81bc295d8b769d9531c44532390d4104705: myapp-1.0.tar.gz


## Deployments
Usage: `deploy deployments APP`

Displays information about the deployments deployed to all the gears of an application:

* deployment date/time
* artifact checksum
* artifact name

Example output:

	$ ./deploy deployments s2
	Gear 51b0dde3a7cfd1abf200006d
	  20130606121412 - 34e2c81bc295d8b769d9531c44532390d4104705 - myapp-1.0.tar.gz
	
	Gear 51b0e483a7cfd1abf2000092
	
	Gear 51b0e665a7cfd1abf20000a5
	  20130606121412 - 34e2c81bc295d8b769d9531c44532390d4104705 - myapp-1.0.tar.gz