variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "ami_id" {
  description = "AMI ID to use for EC2 (ubuntu)"
  type        = string
  default     = "ami-0ecc68efdcd1c6484"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.medium"
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
  default = "subnet-05ccfbd5397e6b2b4"
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
  default = [ "sg-06ba1a4031e8aeebb","sg-0f0adab4772f03d3a","sg-042159acaf1eb62a5","sg-00d23d230210c7d81" ]
}

variable "key_name" {
  description = "EC2 keypair name"
  type        = string
  default     = "neon-edc-key"
}

variable "private_key" {
  description = "Private SSH key contents for provisioners"
  type        = string
  sensitive   = true
}

variable "ssh_user" {
  description = "SSH user on the instance"
  type        = string
  default     = "ubuntu"
}

variable "site_name" {
  description = "Site name (will be used as deployment name & SITES)"
  type        = string
}

variable "compose_directory" {
  description = "Directory on remote instance where compose files are placed"
  type    = string
  default = "/home/ubuntu/frappe-docker"
}

variable "base_domain" {
  type    = string
  default = "cliniexperts.net"
}

variable "registry" {
  description = "Container registry URL"
  type    = string
  default = "registry.gitlab.com"
}

variable "container_registry_username" {
  description = "Registry username"
  type      = string
  sensitive = true
  default   = ""
}

variable "container_registry_pat" {
  description = "Registry PAT / token"
  type      = string
  sensitive = true
  default   = ""
}

# fixed image to use; you said you want this constant in variables.tf
variable "study_site_image" {
  description = "Docker image repository (without tag). Fixed by default."
  type    = string
  default = "registry.gitlab.com/neon2501537/frappe-study-app"
}

# only the tag will be passed by pipeline/API trigger
variable "study_image_tag" {
  description = "Image tag to deploy (passed from pipeline)"
  type        = string
}
