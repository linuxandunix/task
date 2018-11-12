variable "region"
{
    default = "ap-south-1"
}

variable "aws_ubuntu_awis"
{
    default = {
        "ap-south-1" = "ami-04ea996e7a3e7ad6b"
    }
}

variable "environment"{
    type = "string"
}

variable "application" {
    type = "string"
}

variable "key_name" {
    type = "string"
    default = "ec2key"
}

variable "mgmt_ips" {
    default = ["0.0.0.0/0"]
}