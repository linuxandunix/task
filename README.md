# task
main.tf -- The terraform configuration.
variables.tf -- Variables declared in main.tf
ansible_docker_install.yml -- ansible playbook to install docker engine on the hosts.
copy_docker_run_and_execute_script.yml -- ansible playbook to copy and execute nginx_docker.sh
nginx_docker.sh -- Bash script to pull and run nginx container from docker hub
