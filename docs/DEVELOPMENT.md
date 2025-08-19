# Marketplace App Development Guidelines

A Marketplace App leverages the Linode API and Ansible to deploy and configure a single node service. The end-user’s Linode API token must be scoped with appropriate permissions to add and remove the necessary platform resources, such as compute, DNS, storage, etc. In additon, please adhere to the following guidelines for Marketplace apps:

  - We recommend Marketplace applications use Ubuntu 24.04 LTS images when possible. 
  - The deployment of the service should be “hands-off,” requiring no command-line intervention from the user before reaching its initial state. The end user should provide all necessary details via User Defined Variables (UDF) defined in the StackScript, so that Ansible can fully automate the deployment.
  - There is not currently password validation for StackSctript UDFs, therefore, whenever possible credentials should be generated in the [provision.yml](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/apps/linode-marketplace-beef/provision.yml) and provided to the end-user via the credentials file generated in the [post role](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/apps/linode-marketplace-beef/roles/post/tasks/main.yml) .
  - At no time should billable services that will not be used in the final deployment be present on the customer’s account.
  - All Marketplace applications should use fully maintained packages and pinned to the latest stable package per application/service. 
  - All Marketplace applications should include Linux server best practices such as a sudo-user, SSH hardening and basic firewall configurations. 
  - All Marketplace applications should adhere to the best practices for the deployed service, and include security such as SSL whenever possible. 
  - All Marketplace service installations should be minimal, providing no more than dependencies and removing deployment artifacts. 

## Deployment Scripts

All Bash scripts, including the deployment Stackscript for each Marketplace App is kept in the `deployment_scripts` directory. Deployment Stackscripts should adhere to the following conventions.

- The StackScript must implement the [Linux trap command](https://man7.org/linux/man-pages/man1/trap.1p.html) for error handling.
- The primary purposes of the Stackscript is to assign global variables, create a working directory and Python venv before cloning the correct Marketplace App repo.
  - Installations and configurations that are not necessary for supporting the Ansible environment (i.e. Python or Git dependencies) should be performed with Ansible playbooks, and not included in the Stackscript. The StackScript should be as slim as possible, letting Ansible do most of the heavy lifting.
  - All working directories should be cleaned up on successful completion of the Stackscript.
  - A public deployment script must conform to the [Stackscript requirements](https://www.linode.com/docs/guides/writing-scripts-for-use-with-linode-stackscripts-a-tutorial/) and we strongly suggest including a limited number of [UDF variables](https://www.linode.com/docs/guides/writing-scripts-for-use-with-linode-stackscripts-a-tutorial/#user-defined-fields-udfs).

## Ansible Playbooks 

- All Ansible playbooks should generally adhere to the [sample directory layout](https://docs.ansible.com/ansible/latest/user_guide/sample_setup.html#sample-ansible-setup) and best practices/recommendations from the latest Ansible [User Guide](https://docs.ansible.com/ansible/latest/user_guide/index.html).
  - All Ansible playbooks for Marketplace applications should include common [`.ansible-lint`](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/apps/linode-marketplace-wordpress/.ansible-lint), [`.yamllint`](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/apps/linode-marketplace-wordpress/.yamllint), [`ansible.cfg`](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/apps/linode-marketplace-wordpress/ansible.cfg) and `.gitignore`.
  - All Ansible playbooks should use Ansible Vault for initial secrets management. Generated credentials should be provided to the end-user in a standard `.credentials` file located in the sudo user’s home directory. 
  - Whenever possible Jinja should be leveraged to populate a consistent variable naming convention during [node provisioning](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/apps/linode-marketplace-wordpress/provision.yml).
  - It is recommended to import service specific tasks as modular `.yml` files under the application’s `main.yml`. 

Marketplace App playbooks should align with the following sample directory trees. There may be certain applications that require deviation from this structure, but they should follow as close as possible. To use a custom FQDN see [Configure your Linode for Reverse DNS](https://www.linode.com/docs/guides/configure-your-linode-for-reverse-dns/).

Needs update:
```
linode-marketplace-$APP/
  ansible.cfg 
  collections.yml # Ensure to pin to specific version
  provision.yml # Where any credentials should be generated
  requirements.txt # Ensure to pin to specific version
  site.yml
  .ansible-lint
  .yamllint
  .gitignore

  group_vars/
    provisioner/ 
      vars 
  
  roles/
    $elasticsearch/ # Replace with first application component name
      handlers/
        main.yml
      tasks/
        main.yml # Break the install into it's different segments/services 
        install.yml # Install's main application
        ssl.yml # Configures ssl
      templates/
        $FILE.j2
      defaults/
        main.yml # Contains reusable static variables
    $kibana/ # Replace with first application component name
      handlers/
        main.yml
      tasks/
        main.yml # Break the install into it's different segments/services 
        install.yml # Install's main application
        configure.yml # Configures kibana with Elasticsearch
      templates/
        $FILE.j2
      defaults/
        main.yml # Contains reusable static variables       
    common/ 
      handlers/ 
        main.yml
      tasks/ 
        main.yml # Includes all the helper functions
    post/ 
     handlers/ 
        main.yml
      tasks/ 
        main.yml # Creates the credentials file & sets the MOTD
      templates/
        MOTD.j2
```
As general guidelines: 
  - The `roles` should general conform to the following standards:
    - `common` - including preliminary configurations and Linux best practices.
    - `$app_name` - including all necessary plays for service/app deployment and configuration. Within the app role, the installation should be broken down into seperate tasks. For example, the '$app_name' install should only include the steps to install the app and ssl.yml should handle the ssl generation for the cluster.
    - `post` - any post installation tasks such as clean up operations and generating additonal user credentials. This should include the creation of a credentials file in `/home/$SUDO_USER/.credentials` and a MOTD (Message of the Day) file to display after login to provide some additional direction after the deployment. 

## Helper Functions

Helper functions are static roles that can be called at will when we are trying to accomplish a repeatable system task. Instead of rewriting the same function for multiple One-Click Apps, we can simply import the Helper role to accomplish the same effect. This results in basic system configurations being performed predictably and reliably, without the variance of individual authors.

For more information on roles please refer to the [Ansible documentation](https://docs.ansible.com/ansible/latest/user_guide/playbooks_reuse_roles.html#using-roles-at-the-play-level).

## User Defined Fields (UDF)
Below are examples of UDFs your deployment can use in the [deployment StackScript](../deployment_scripts/). For consistency, please name the deployment script `$app-deploy.sh` (example [tdb]())

```
## Cluster App Settings
TBD
```
### UDF Tips and Tricks 

- UDFs without a `default` are required. 
- UDFs with a `default` will write that default if the customer does not enter a value. Non printing characters are treated literally in defaults.
- UDFs containing the string `password` within the `name` will display as obfuscated dots in the Cloud Manager. They are also encrypted on the host and do not log.
- A UDF containing `label="$label" header="Yes" default="Yes" required="Yes"` will display as a header in the Cloud Manager, but does not affect deployment.

## Testing on Linode

To test your Marketplace App you can provision and deploy the app to Linodes on your account. Note that billing will occur for any Linode instances deployed.

To test your Marketplace App on Linode infrastucutre, copy and paste `$app-deploy.sh` into a new Stackscript on your account. Then update the Git Repo section of `$app-deploy.sh` to include your fork of the Marketplace repo. Logging output can be viewed in `/var/log/stackscript.log` in the deployed instance.