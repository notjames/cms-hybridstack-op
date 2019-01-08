
# For AWS infrastructure WORK IN PROGRESS - NOT COMPLETE - DO NOT USE
For TL;DR - see QUICK START

## General Requirements
 * You must already have valid AWS credentials set up and saved in your `$HOME/.aws/credentials`.
 * In a couple of the examples below, a variable is created by reading a private base64 encoded key. [YOU DO NOT NEED TO CREATE THE KEY!](#AWS%20Key%20Management) If an error occurs because the key does not exist, you can safely ignore the error. The AWS key management script will create a key based off the `$CLUSTER_ID`. In the event that you've created a stack with the same `$CLUSTER_ID`, the script will import that key to AWS. If the key doesn't exist, the script will create a new key pair and import it to AWS saving the base64 encoded key with proper permissions to `$HOME/.ssh`.

### [optctl](https://opctl.io/docs/getting-started/opctl.html)
`optctl` is currently the preferred method for creating these CF stacks. *NOTE* In the following example, `$CLUSTER_ID`, `$UID`, and `$GID` were set as an environment variables:

### AWS Key management:
  1. The private key used for AWS (`CLUSTER_PRIVATE_KEY`) cli transactions will be named from `CLUSTER_ID`. If an existing private key exists as `$HOME/.ssh/${CLUSTER_ID}Key.pem` then that key will be imported to AWS if it does not already exist in AWS. If it exists in AWS then that key pair will be used for all AWS cli transactions. If you specify a `CLUSTER_ID` for which a key has not been created, the tooling will create the key pair and import it to AWS.
  1. The `CLUSTER_PRIVATE_KEY` env variable does not need to be set because key management depends on the `CLUSTER_ID`, which is mandatory. However, the option exists to specify a base64 encoded private key stored in the env variable `$CLUSTER_PRIVATE_KEY`. Note that specifying a private key in this manner is yet untested. In order to create a properly base64 encoded key for this variable, one must do the following on a PEM encoded private key:
    * `< /path/to/private_key.pem base64 | tr -d '\r\n' | tr -d ' '`

### Github Application Token
An application token is required so this op can pull samsung repos for installation IE cma, cma-ssh, etc. Please review the documentation located here on how to set one up.

### QUICK START:
Running the whole thing right now:
  * Set required environment variables
    * `export CLUSTER_ID=<cluster-name> # CLUSTER_ID is an arbitrary name you make up.`
    * `export GID=$(id -g) UID`
    * `export githubUsername=<username> githubPassword=<application token>`
    * OR in one line: `export UID GID=$(id -g) CLUSTER_ID=<CLUSTER_ID> githubUsername=<your_gh_username> githubPassword=<your_gh_token>`
  * Make everything happen:
    * From the parent directory of the `.opspec` directory run the following:
    `opctl run .`

### OK, but you want to know the details? Explanation:
The following guidelines are necessary to run op:

  * Each _op_ stored in `.opspec` declared in `op.yml` files of each directory define the work that will be done. Explaining how `opctl` works is outside the scope of this README. One should read the [`opctl` documentation](http://opctl.io/documentation).
  * The most important environment variable/runtime setting is `CLUSTER_ID`, which is an arbitrary name you create.
  * The following are environment variables that can be set if the defaults are not what you need or want:
    * AWS_DEFAULT_REGION   (default: us-west-2)
    * AVAILABILITY_ZONE    (default: us-west-2b)
    * CLUSTER_USERNAME     (default: $OS_TYPE)
    * CLUSTER_PRIVATE_KEY  (default: nil)
    * OS_TYPE              (default: centos)
  * Instead of setting environment variables, one can use the `-a` argument to `opctl` e.g. `opctl -a aws-default-region=us-west-2 -a ...`
  * The following environment variable must be set:
    * `export CLUSTER_ID=<cluster-name>`
    * `export GID=$(id -g) UID`
    * `export githubUsername=<username> githubPassword=<application token>`

### Ops can be run individually
  * After setting the required environment variables, one can run just the AWS cloudformation bits and nothing else by running:
  * `opctl run aws/01-infrastructure`
    * That will create four AWS instances:
      * manager controller
      * manager worker
      * managed controller
      * managed worker
  * `opctl run aws/02-bootstrap-cmc`
    * That will install docker, kubernetes, and helm on the manager master node.
  * `opctl run aws/03-deploy-cmc`
    * That will perform the necessary steps of installing the CMC, CMA, and friends charts.

## IMPORTANT NOTES
  * Currently, the AWS instances are not set up behind a security group to mimic the VDI environment. That is a TODO item as yet.
  * No helm charts are currently being installed into the Master Control Plane, though the plumbing is there to do it.
  * This project is a WIP and changes are coming down the pike which will likely significantly change the way this project works (IE using KinD).

## Information - everything below this line is for a deeper dive.
Most of this is up to date, but there may be some disparate information as this project is still under heavy development.

### Create the AWS instances
  * `cd .opspec/aws`
  * `export CLUSTER_ID=<cluster_id>`
  * `docker build -t cm-cf-createstack:latest .`
      for cluster_type in manager managed; do
        (docker run -v $PWD:/root \
                    -v $HOME/.ssh:/root/.ssh \
                    -v $HOME/.aws:/root/.aws \
              $(echo " OS_TYPE=centos
                       CLUSTER_ID=$CLUSTER_ID
                       AWS_DEFAULT_REGION=us-west-2
                       AVAILABILITY_ZONE=us-west-2b
                       CLUSTER_USERNAME=centos
                       INSTANCE_TYPE=c4.large
                       CLUSTER_TYPE=$cluster_type
                       $(bin/export_aws_creds)" | \
                sed 's# \+# -e #g' \
                      -i cm-cf-createstack:latest &)
      done`

### Bootstrap the manager controller (master)
  * NOTE THAT THE PROCESS OR USER RUNNING THIS MUST SET AN ENV VARIABLE CALLED `UID` TO $(id -u) e.g. export UID
  * From the root of the repo: `cd .opspec/aws/bin`
  * `./bootstrap-nodes.sh -ct manager -nt master`
    * This command will automatically determine the public IP for the master and it will bootstrap the master control instance and start Kubernetes. The script will capture the kubeadm join string for worker nodes.

### Bootstrap the manager worker
  * `./bootstrap-nodes.sh -ct manager -nt worker`
    * This command will bootstrap the worker and join it to the master

## Deploying CMC charts (WIP -- currently incomplete)
* Up to this point we have managed to instantiate AWS nodes and install Kubernetes in a control plane and on worker nodes, which have joined to the control plane. Now we need to install our application software for cluster management.
    * It  will then install helm
    * It tries to install the cmc stuff, but that currently does not yet work due to restrictions on repos among other things.

