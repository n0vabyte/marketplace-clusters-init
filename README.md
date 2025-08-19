# Akamai Cloud Marketplace Cluster Apps

The Akamai Cloud Marketplace is designed to make it easier for developers and companies to share [One-Click Clusters](https://www.linode.com/marketplace/) with the Linode community. One-Click Cluster apps modular solutioning tools written as Ansible playbooks. The Akamai Cloud Marketplace allows users to quickly deploy services and perform essential configurations on a Linode compute instance's post boot sequence.

A Marketplace deployment refers to an application (single service on a single node) or a cluster (multi-node clustered service such as Galera). A combination of Linode [StackScripts](https://techdocs.akamai.com/cloud-computing/docs/stackscripts) and Ansible playbooks give the Marketplace a one-click installation and delivery mechanism for deployments. The end user is billed just for the underlying cloud resources (compute instances, storage volumes, etc) in addition to any applicable BYOLs.

## Marketplace App Development Guidelines.

A Marketplace application consists of three major components: 
- Stackscript, 
- Ansible playbooks
- A public GIT repository to clone from

### Stackscript

A [Stackscript](https://techdocs.akamai.com/cloud-computing/docs/write-a-custom-script-for-use-with-stackscripts) is a Bash script that is stored on Linode hosts and is accessible to all customers.

### Ansible Playbook

All Ansible playbooks should generally adhere to the [sample directory layout](https://docs.ansible.com/ansible/latest/user_guide/sample_setup.html#sample-ansible-setup) and best practices/recommendations from the latest Ansible [User Guide](https://docs.ansible.com/ansible/latest/user_guide/index.html).

### Helper Functions

Helper functions are static roles that can be called at will when we are trying to accomplish a repeatable system task. Instead of rewriting the same function for multiple One-Click Apps, we can simply import the Helper role to accomplish the same effect. This results in basic system configurations being performed predictably and reliably, without the variance of individual authors.

More detailed information on the available helper functions and variables can be found in the [utils](apps/utils/README.md) root directory.

For more information on roles please refer to the [Ansible documentation](https://docs.ansible.com/ansible/latest/user_guide/playbooks_reuse_roles.html#using-roles-at-the-play-level).

## Creating Your Own

For more information on creating and submitting a Partner App for the Akamai Cloud Marketplace please see [Contributing](docs/CONTRIBUTING.md) and [Development](docs/DEVELOPMENT.md).
