##AWS specific details



provider "aws" {
  region = "ap-south-1"
  shared_credentials_file = "~/.credentials"
  profile = "TASK"
 }



##network components

#vpc & subnets

 resource "aws_vpc" "souravtask" {
  cidr_block = "10.0.0.0/16" # Defines overall VPC address space
  enable_dns_hostnames = true # Enable DNS hostnames for this VPC
  enable_dns_support = true # Enable DNS resolving support for this VPC
  tags{
      Name = "VPC-${var.environment}" # Tag VPC with name
  }
}

resource "aws_subnet" "pub-web-az-a" {
  availability_zone = "ap-south-1a" # Define AZ for subnet
  cidr_block = "10.0.11.0/24" # Define CIDR-block for subnet
  map_public_ip_on_launch = true # Map public IP to deployed instances in this VPC
  vpc_id = "${aws_vpc.souravtask.id}" # Link Subnet to VPC
  tags {
      Name = "Subnet-ap-south-1a-Web" # Tag subnet with name
  }
}

resource "aws_subnet" "pub-web-az-b" {
    availability_zone = "ap-south-1b"
    cidr_block = "10.0.12.0/24"
    map_public_ip_on_launch = true
    vpc_id = "${aws_vpc.souravtask.id}"
      tags {
      Name = "Subnet-ap-south-1b-Web"
  }
}

resource "aws_subnet" "priv-db-az-a" {
  availability_zone = "ap-south-1a"
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = false
  vpc_id = "${aws_vpc.souravtask.id}"
  tags {
      Name = "Subnet-ap-south-1a-DB"
  }
}

resource "aws_subnet" "priv-db-az-b" {
    availability_zone = "ap-south-1b"
    cidr_block = "10.0.2.0/24"
    map_public_ip_on_launch = false
    vpc_id = "${aws_vpc.souravtask.id}"
      tags {
      Name = "Subnet-ap-south-1b-DB"
  }
}



#IGW

resource "aws_internet_gateway" "inetgw" {
  vpc_id = "${aws_vpc.souravtask.id}"
  tags {
      Name = "IGW-VPC-${var.environment}-Default"
  }
}


#Route table

resource "aws_route_table" "eu-default" {
  vpc_id = "${aws_vpc.souravtask.id}"

  route {
      cidr_block = "0.0.0.0/0" # Defines default route 
      gateway_id = "${aws_internet_gateway.inetgw.id}" # via IGW
  }

  tags {
      Name = "Route-Table-EU-Default"
  }
}

resource "aws_route_table_association" "ap-south-1a-public" {
  subnet_id = "${aws_subnet.pub-web-az-a.id}"
  route_table_id = "${aws_route_table.eu-default.id}"
}

resource "aws_route_table_association" "ap-south-1b-public" {
  subnet_id = "${aws_subnet.pub-web-az-b.id}"
  route_table_id = "${aws_route_table.eu-default.id}"
}


resource "aws_route_table_association" "ap-south-1a-private" {
  subnet_id = "${aws_subnet.priv-db-az-a.id}"
  route_table_id = "${aws_route_table.eu-default.id}"
}

resource "aws_route_table_association" "ap-south-1b-private" {
  subnet_id = "${aws_subnet.priv-db-az-b.id}"
  route_table_id = "${aws_route_table.eu-default.id}"
}


#EC2 instance,related subnets, SSH key pair

resource "aws_instance" "NGINXA" {
    ami = "${lookup(var.aws_ubuntu_awis,var.region)}"
    instance_type = "t2.micro"
    tags {
        Name = "${var.environment}-nginx001"
        Environment = "${var.environment}"
        sshUser = "ubuntu"
    }
    subnet_id = "${aws_subnet.pub-web-az-a.id}"
    key_name = "${aws_key_pair.keypair.key_name}"
    vpc_security_group_ids = ["${aws_security_group.WebserverSG.id}"]
}
resource "aws_instance" "NGINXB" {
    ami = "${lookup(var.aws_ubuntu_awis,var.region)}"
    instance_type = "t2.micro"
    tags {
        Name = "${var.environment}-nginx002"
        Environment = "${var.environment}"
        sshUser = "ubuntu"
    }
    subnet_id = "${aws_subnet.pub-web-az-b.id}"
    key_name = "${aws_key_pair.keypair.key_name}"
    vpc_security_group_ids = ["${aws_security_group.WebserverSG.id}"]
}
resource "aws_instance" "BASTIONHOST" {
    ami = "${lookup(var.aws_ubuntu_awis,var.region)}"
    instance_type = "t2.micro"
    tags {
        Name = "${var.environment}-BASTION"
        Environment = "${var.environment}"
        sshUser = "ubuntu"
    }
    subnet_id = "${aws_subnet.pub-web-az-a.id}"
    key_name = "${aws_key_pair.keypair.key_name}"
    vpc_security_group_ids = ["${aws_security_group.bastionhostSG.id}"]
}

resource "aws_elb" "lb" {
    name_prefix = "${var.environment}-"
    subnets = ["${aws_subnet.pub-web-az-a.id}", "${aws_subnet.pub-web-az-b.id}"]
    health_check {
        healthy_threshold = 2
        unhealthy_threshold = 2
        timeout = 3
        target = "HTTP:80/"
        interval = 30
    }
    listener {
        instance_port = 80
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }
    cross_zone_load_balancing = true
    instances = ["${aws_instance.NGINXA.id}", "${aws_instance.NGINXB.id}"]
    security_groups = ["${aws_security_group.LoadBalancerSG.id}"]
}


#Loadbalancer
##we are using the bastion hosts as proxies for the instances in the private subnets to access the internet via a squid proxy which will be installed to the bastion-hosts by Ansible.

resource "aws_security_group" "LoadBalancerSG"
{
    name = "LoadBalancerSG"
    vpc_id = "${aws_vpc.souravtask.id}"
    description = "Security group for load-balancers"
    ingress {
        from_port = 80
        to_port = 80
        protocol = "TCP"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow incoming HTTP traffic from anywhere"
    }
    ingress {
        from_port = 443
        to_port = 443
        protocol = "TCP"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow incoming HTTPS traffic from anywhere"
    }

    egress {
        from_port = 80
        to_port = 80
        protocol = "TCP"
        security_groups = ["${aws_security_group.WebserverSG.id}"]
    }

    egress {
        from_port = 443
        to_port = 443
        protocol = "TCP"
        security_groups = ["${aws_security_group.WebserverSG.id}"]
    }

    tags
    {
        Name = "SG-Loadbalancer"
    }
}
resource "aws_security_group" "WebserverSG"
{
    name = "WebserverSG"
    vpc_id = "${aws_vpc.souravtask.id}"
    description = "Security group for webservers"
    ingress {
        from_port = 22
        to_port = 22
        protocol = "TCP"
        security_groups = ["${aws_security_group.bastionhostSG.id}"]
        description = "Allow incoming SSH traffic from Bastion Host"
    }
  ingress {
      from_port = -1
      to_port = -1
      protocol = "ICMP"
      security_groups = ["${aws_security_group.bastionhostSG.id}"]
      description = "Allow incoming ICMP from management IPs"
  }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        self = true
    }
    egress {
        from_port = 3128
        to_port = 3128
        protocol = "TCP"
        security_groups = ["${aws_security_group.bastionhostSG.id}"]
    }
    tags
    {
        Name = "SG-WebServer"
    }
}

resource "aws_security_group" "bastionhostSG" {
  name = "BastionHostSG"
  vpc_id = "${aws_vpc.souravtask.id}"
  description = "Security group for bastion hosts"
  ingress {
      from_port = 22
      to_port = 22
      protocol = "TCP"
      cidr_blocks = ["${var.mgmt_ips}"]
      description = "Allow incoming SSH from management IPs"
  }

  ingress {
      from_port = -1
      to_port = -1
      protocol = "ICMP"
      cidr_blocks = ["${var.mgmt_ips}"]
      description = "Allow incoming ICMP from management IPs"
  }
  egress {
      from_port = 0
      to_port = 0
      cidr_blocks = ["0.0.0.0/0"]
      protocol = "-1"
      description = "Allow all outgoing traffic"
  }
  tags {
      Name = "SG-Bastionhost"
  }
}

resource "aws_security_group_rule" "lbhttpaccess" {
    security_group_id = "${aws_security_group.WebserverSG.id}"
    type = "ingress"
    from_port = 80
    to_port = 80
    protocol = "TCP"
    source_security_group_id = "${aws_security_group.LoadBalancerSG.id}"
    description = "Allow Squid proxy access from loadbalancers"
}

resource "aws_security_group_rule" "lbhttpsaccess" {
    security_group_id = "${aws_security_group.WebserverSG.id}"
    type = "ingress"
    from_port = 443
    to_port = 443
    protocol = "TCP"
    source_security_group_id = "${aws_security_group.LoadBalancerSG.id}"
    description = "Allow Squid proxy access from loadbalancers"
}

resource "aws_security_group_rule" "webproxyaccess" {
    security_group_id = "${aws_security_group.bastionhostSG.id}"
    type = "ingress"
    from_port = 3128
    to_port = 3128
    protocol = "TCP"
    source_security_group_id = "${aws_security_group.WebserverSG.id}"
    description = "Allow Squid proxy access from webservers"
}


#SSH key-pair
##we'll have Terraform generate a key-pair.  Finally we tell Terraform to output the by using the Terraform output command. 

resource "tls_private_key" "privkey"
{
    algorithm = "RSA" 
    rsa_bits = 4096
}
resource "aws_key_pair" "keypair"
{
    key_name = "${var.key_name}"
    public_key = "${tls_private_key.privkey.public_key_openssh}"
}
output "private_key" {
  value = "${tls_private_key.privkey.private_key_pem}"
  sensitive = true
}



#Ansible inventory

resource "ansible_host" "BASTIONHOSTA" {
  inventory_hostname = "${aws_instance.BASTIONHOSTA.public_dns}"
  groups = ["security"]
  vars
  {
      ansible_user = "ubuntu"
      ansible_ssh_private_key_file="/opt/terraform/aws_basic/privkey.pem"
      ansible_python_interpreter="/usr/bin/python3"
  }
}

resource "ansible_host" "BASTIONHOSTB" {
  inventory_hostname = "${aws_instance.BASTIONHOSTB.public_dns}"
  groups = ["security"]
  vars
  {
      ansible_user = "ubuntu"
      ansible_ssh_private_key_file="/opt/terraform/aws_basic/privkey.pem"
      ansible_python_interpreter="/usr/bin/python3"
  }
}


resource "ansible_host" "WEB001" {
  inventory_hostname = "${aws_instance.NGINXA.private_dns}"
  groups = ["web"]
  vars
  {
      ansible_user = "ubuntu"
      ansible_ssh_private_key_file="/opt/terraform/aws_basic/privkey.pem"
      ansible_python_interpreter="/usr/bin/python3"
      ansible_ssh_common_args= " -o ProxyCommand=\"ssh -i /opt/terraform/aws_basic/privkey.pem -W %h:%p -q ubuntu@${aws_instance.BASTIONHOSTA.public_dns}\""
      proxy = "${aws_instance.BASTIONHOSTA.private_ip}"
  }
}

resource "ansible_host" "WEB002" {
  inventory_hostname = "${aws_instance.WEBB.private_dns}"
  groups = ["web"]
  vars
  {
      ansible_user = "ubuntu"
      ansible_ssh_private_key_file="/opt/terraform/aws_basic/privkey.pem"
      ansible_python_interpreter="/usr/bin/python3"
      ansible_ssh_common_args= " -o ProxyCommand=\"ssh -i /opt/terraform/aws_basic/privkey.pem -W %h:%p -q ubuntu@${aws_instance.BASTIONHOSTB.public_dns}\""
      proxy = "${aws_instance.BASTIONHOSTB.private_ip}"
  }
}








