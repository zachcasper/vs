# Wordpress and MySQL Example using AWS RDS

This tutorial is based on the staged [Create a Resource Type in Radius](https://red-sea-07f97dc1e-1409.westus2.3.azurestaticapps.net/tutorials/tutorial-resource-type/) tutorial. The only difference between that tutorial and this one is the inclusion of using an AWS RDS database.

## Prerequisites

1. Radius CLI at least version 0.46 installed on the workstation
1. Node.js installed on the workstation
1. An EKS cluster
1. A Git repository for storing the Terraform configurations; this tutorial will assumes anonymous access to the Git repository, if that is not the case see [this documentation](https://red-sea-07f97dc1e-1409.westus2.3.azurestaticapps.net/guides/recipes/terraform/howto-private-registry/)

## Install Radius on EKS
This tutorial will set up two environments: dev and test. The dev environment will use recipes which deploy all resources to the Kubernetes cluster. The test environment will deploy containers to Kubernetes and other resources, such as databases, to AWS.

### Setup AWS variables

Set some variables for your Azure subscription and resource group.
```
AWS_REGION=
AWS_ACCOUNTID=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_EKS_CLUSTER_NAME=
```
Get the kubecontext for your EKS cluster if it's not already set.
```
aws eks update-kubeconfig --region $AWS_REGION --name $AWS_EKS_CLUSTER_NAME
```
### Install Radius.
```
rad install kubernetes 
```

### Create the dev environment
All resources including Radius environments reside in a resource group just like in Azure. Since we will be deploying the same application to a dev and a test environment, we need two separate resource groups (unless we wanted to rename our application but that defeats the purpose).

Create a resource group for the dev environment.
```
rad group create dev
```
Create a dev environment in the dev resource group.
```
rad environment create dev --group dev
```
Set up the Radius CLI configuration file. Radius uses the term workspace to refer to a specific combination of Radius installation, environment, and group.
```
rad workspace create kubernetes dev --context $EKS_CLUSTER_NAME --environment dev --group dev
```
### Create the test environment
Create a resource group for the test environment.
```
rad group create test
```
Create a test environment in the test resource group.
```
rad environment create test --group test
```
Set the Radius CLI configuration file.
```
rad workspace create kubernetes test --context $EKS_CLUSTER_NAME --environment test --group test
```
### Setup AWS authentication
In order for Radius to deploy resources to AWS, it must be able to authenticate. Radius itself must be authenticated to AWS even if you are authenticated on your local workstation. If Radius is not authenticated and you run `rad deploy`, the deployment will fail. Radius can authenticate to AzureAWS using either a [access key](https://docs.radapp.io/guides/operations/providers/aws-provider/howto-aws-provider-access-key/) or [IRSA](https://docs.radapp.io/guides/operations/providers/aws-provider/howto-aws-provider-irsa/). This tutorial assumes an access key.

Add the access key as a credential in Radius. Credentials today are stored at the Radius top level. In the future, we plan to move credentials to the environment level to enable multiple subscriptions.
```
rad credential register aws access-key --access-key-id $AWS_ACCESS_KEY_ID --secret-access-key $AWS_SECRET_ACCESS_KEY
```
Update the dev and test environments with AWS details.
```
rad environment update dev --aws-region $AWS_REGION --aws-account-id $AWS_ACCOUNTID --workspace dev
rad environment update test --aws-region $AWS_REGION --aws-account-id $AWS_ACCOUNTID --workspace test
```

## Create MySQL resource type
```
rad resource-type create mySQL -f types.yaml
```
## Register the PostgreSQL recipe

Commit the recipes directory into a Git repository. This directory has two Terraform recipes for deploying a PostgreSQL database, one for Kubernetes and one for AWS. The Kubernetes recipe will be used for the dev environment while the Azure recipe will be used for the test environment.

### Dev environment

Register the Kubernetes recipe in the dev environment.
```
rad recipe register default \
  --workspace dev \
  --resource-type Radius.Resources/mySQL \
  --template-kind terraform \
  --template-path git::https://github.com/zachcasper/vs.git//recipes/kubernetes/mysql
```
Some explaination of this command is warranted. 

* `rad recipe register` – This is creating a pointer to a Terraform configuration or a Bicep template which will be called when a resource is created in Radius.
* `rad recipe register default` – Each recipe has a name but you should use default. This is legacy functionality which will be retired. With older resource types which are built into Radius such as Redis and MongoDB, developers could specify a named recipe to be used to deploy the resource. The newer resource types such as the PostgreSQL resource type we are defining here will not allow developers to specify a recipe name. 
* `--template-path git::https://github.com/zachcasper/vs.git//recipes/kubernetes/postgresql` – This is the path to the Terraform configuration. Radius uses the generic Git module source as [documented here](https://developer.hashicorp.com/terraform/language/modules/sources#generic-git-repository). In the example here, the Git repository on GitHub is UBS. The `//` indicates a sub-module or a sub-directory and postgresql is the directory containing the main.tf file.

### Test environment

Register the AWS recipe in the test environment.
```
rad recipe register default \
  --workspace test \
  --resource-type Radius.Resources/postgreSQL \
  --template-kind terraform \
  --template-path git::https://github.com/zachcasper/vs.git//recipes/aws/mysql \
```

## Create the Bicep extension

Since we created a new resource type, we must tell Bicep how to handle it. This is performed by creating a Bicep extension. Bicep extensions can be stored in either Azure Container Registry or on the file system. This example will use the file system. The documentation for using a private module registry is [here](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/quickstart-private-module-registry?tabs=azure-cli).

Create the Bicep extension.
```
rad bicep publish-extension -f types.yaml --target radiusResources.tgz
```
Update the bicepconfig.json file to include the extension. The bicepconfig.json included in this example has already been updated. Consult the [documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-config) on having multiple bicepconfig.json files if you are interested. Note that when you when your bicepconfig.json file is stored in a different directory than your .tgz extension file, you must reference the extension file using the full path name, not a relative path.

## Deploy the wordpress application to dev
The dev environment uses the Kubernetes MySQL recipe, so MySQL will be ran as a container on the cluster.

Make sure you are using the dev environment.
```
rad workspace switch dev
```
Deploy the Wordpress application.
```
rad deploy wordpress.bicep
```
### Port forward and open the application
Use kubectl to port forward the frontend pod. Typically in a shared environment, the container would have a gateway resource which would setup an ingress controller using Contour. Since we installed Radius without Contour, the gateway resource will not work. 
```
kubectl port-forward `kubectl get pods -n dev-wordpress | grep frontend | awk '{print $1}'` 8080:80 -n dev-wordpress
```
Open http://localhost:8080 in your browser. You should see the Wordpress language selection page. If Wordpress cannot connect to the database, you will get a "Error establishing a database connection" error.

### Examine the resources deployed
Run the rap app graph command.
```
rad app graph -a wordpress
```
You will see that a Kubernetes Deployment, Service, ServiceAccount, Role, and RoleBinding were created for the Wordpress container. In the very near future you will also see the Kubernetes resources for the MySQL database. This doesn't work quite yet for custom resource types like MySQL.

## Deploy the Wordpress application to test
Switch to the test enviornment
```
rad workspace switch test
```
Deploy the Wordpress application.
```
rad deploy wordpress.bicep
```
### Port forward and open the application
Use the same kubectl port-forward command as before, but change the namespace from dev-wordpress to test-wordpress. 

### Examine the resources deployed
Use the same `rap app graph -a wordpress` command and confirm that Radius has created the MySQL database on AWS.

## Clean up
Delete both applications.
```
rad app delete --workspace dev
rad app delete --workspace test
```
Verify the pods are terminated on the Kubernetes cluster.
```
kubectl get pods -A
```
Delete the namespaces if the pods still exist. This is not expected but just to make sure. When you delete the application the namespaces are retained but the pods should be destroyed. 
```
kubectl delete namespace dev-wordpress
kubectl delete namespace test-wordpress
```
Verify the RDS database has been deleted via the AWS console. This is not expected just to make sure.

Optionally, delete the Radius environments, Radius resource groups, and associated workspaces.
```
rad environment delete dev
rad group delete dev
rad workspace delete dev
rad environment delete test
rad group delete test
rad workspace delete test
```
Optionally, delete the postgreSQL resource type.
```
rad delete resource-type Radius.Resources/mySQL
```
