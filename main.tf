terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket = "clini-experts-terraform-state"
    key    = "study-app/terraform.tfstate"
    region = "ap-south-1"
  }
}

# EC2 Instance
resource "aws_instance" "ec2_instance" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name      = var.site_name
    AutoSchedule = "true"
  }
}

data "aws_route53_zone" "base" {
  name       = var.base_domain
  private_zone = false
}

resource "aws_route53_record" "study_site_record" {
  zone_id = data.aws_route53_zone.base.zone_id
  name = "${var.site_name}.dev.${var.base_domain}"
  type = "A"
  ttl = 300
  records = [aws_instance.ec2_instance.public_ip]
}

# Install docker on EC2 and login to registry
module "install_docker" {
  source = "./modules/install-docker"

  public_ip = aws_instance.ec2_instance.public_ip
  private_key = var.private_key
  registry    = var.registry
  username    = var.container_registry_username
  pat         = var.container_registry_pat
  instance_id = aws_instance.ec2_instance.id

  # ensure module runs after instance creation
  depends_on = [aws_instance.ec2_instance]
}

# random passwords
resource "random_password" "frappe_site_password" {
  length           = 16
  special          = true
  override_special = "-_.~"
}

resource "random_password" "frappe_db_root_password" {
  length  = 32
  special = false
}

locals {
  # full image that will be used by compose
  full_image = "${var.study_site_image}:${var.study_image_tag}"

  # static envs that may come from user
  static_env_vars = { 
    APPS = "edc_study"
  }

  # envs we always inject
  generated_envs = {
    "ADMIN_PASSWORD"          = random_password.frappe_site_password.result
    "DB_ROOT_PASSWORD"        = random_password.frappe_db_root_password.result
    "SITES"                   = "${var.site_name}.dev.${var.base_domain}"
    "FRAPPE_SITE_NAME_HEADER" = "${var.site_name}.dev.${var.base_domain}"
    "DEPLOYMENT"              = var.site_name
    "tag"                     = var.study_image_tag
    "image"                   = var.study_site_image
  }

  combined_env_vars = merge(local.static_env_vars, local.generated_envs)
}

# create .env and upload docker-compose files
resource "null_resource" "setup_frappe_site_secrets"{
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${var.compose_directory}",
      "rm -f ${var.compose_directory}/* || true"
    ]
  }

  provisioner "file" {
    # base .env (template) present in files/frappe-docker/.env
    source      = "files/frappe-docker/.env"
    destination = "${var.compose_directory}/.env"
  }

  provisioner "remote-exec" {
    inline = [
      "echo \"# injected envs from terraform\" >> ${var.compose_directory}/.env",
      "echo \"${join("\n", [for k, v in local.combined_env_vars : "${k}=${v}"])}\" >> ${var.compose_directory}/.env"
    ]
  }
  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = var.private_key
    host        = aws_instance.ec2_instance.public_ip
  }

  triggers = {
    instance_id = aws_instance.ec2_instance.id
    env_hash    = sha256(join(",", [for k, v in local.combined_env_vars : "${k}=${v}"]))
    compose_hash = sha1(join("", [for f in fileset("files/frappe-docker", "**/*") : filesha1("files/frappe-docker/${f}")]))
  }

  depends_on = [module.install_docker]
}

resource "null_resource" "setup_frappe_site" {

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = var.private_key
    host        = aws_instance.ec2_instance.public_ip
  }
  
  provisioner "file" {
    source      = "files/frappe-docker/docker-compose"
    destination = "${var.compose_directory}/docker-compose"
  } 
  provisioner "file" {
    # upload the parent prod file and the compose fragments directory
    source      = "files/frappe-docker/prod.docker-compose.yml"
    destination = "${var.compose_directory}/prod.docker-compose.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "set -o errexit",
      "cd ${var.compose_directory} || exit 1",
      # ensure docker compose v2 is used - uses 'docker compose'
      "docker image prune -af || true",
      "docker compose -p ${var.site_name} -f ${var.compose_directory}/prod.docker-compose.yml pull > docker-pull.log 2>&1 && echo 'Containers pulled successfully' || (echo 'Failed to pull containers' && sed -n '1,200p' docker-pull.log && exit 1)",
      "docker compose -p ${var.site_name} -f ${var.compose_directory}/prod.docker-compose.yml up -d > /dev/null 2>&1 && echo 'Containers started successfully' || (docker compose -p ${var.site_name} -f ${var.compose_directory}/prod.docker-compose.yml logs -n 100 && exit 1)",
      "docker image prune -af || true"
    ]
    on_failure = fail
  }


  triggers = {
    instance_id = aws_instance.ec2_instance.id
    env_hash    = sha256(join(",", [for k, v in local.combined_env_vars : "${k}=${v}"]))
    compose_hash = sha1(join("", [for f in fileset("files/frappe-docker", "**/*") : filesha1("files/frappe-docker/${f}")]))
  }

  depends_on = [null_resource.setup_frappe_site_secrets]
}

# outputs
output "ec2_public_ip" {
  value = aws_instance.ec2_instance.public_ip
}

output "ec2_private_ip" {
  value = aws_instance.ec2_instance.private_ip
}

output "ec2_instance_id" {
  value = aws_instance.ec2_instance.id
}

output "site_hostname" {
  value = "${var.site_name}.dev.${var.base_domain}"
}

output "admin_password" {
  value     = random_password.frappe_site_password.result
  sensitive = true
}

output "db_root_password" {
  value     = random_password.frappe_db_root_password.result
  sensitive = true
}
