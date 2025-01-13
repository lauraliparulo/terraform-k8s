provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}
#****** VPC Start ******#

resource "aws_vpc" "kube_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true 
  tags = {
    Name = "K8S VPC"
  }
}



resource "random_shuffle" "az" {
  input        = ["${var.region}a", "${var.region}b", "${var.region}c"]
  result_count = 1
}

resource "aws_subnet" "kube_public_subnet" {
  vpc_id            = aws_vpc.kube_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = random_shuffle.az.result[0]

  tags = {
    Name = "K8S Subnet"
  }
}

resource "aws_internet_gateway" "kube_internet_gateway" {
  vpc_id = aws_vpc.kube_vpc.id

  tags = {
    Name = "K8S Internet Gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.kube_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kube_internet_gateway.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.kube_internet_gateway.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.kube_public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "kube_security_group" {
  name   = "K8S Ports"
  vpc_id = aws_vpc.kube_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#****** VPC END ******#

resource "random_string" "s3name" {
  length = 9
  special = false
  upper = false
  lower = true
}

resource "aws_s3_bucket" "s3_kube_bucket" {
  bucket = "k8s-${random_string.s3name.result}"
  force_destroy = true
 depends_on = [
    random_string.s3name
  ]
}

resource "aws_s3_bucket_ownership_controls" "s3_bucket_acl_ownership" {
  bucket = aws_s3_bucket.s3_kube_bucket.id
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "s3_bucket_acl" {
  bucket = aws_s3_bucket.s3_kube_bucket.id
  acl    = "private"
  depends_on = [aws_s3_bucket_ownership_controls.s3_bucket_acl_ownership]
}

resource "null_resource" "update_nginx_manifest_file_to_s3" {
    provisioner "local-exec" {
        command     = "aws s3 cp nginx.yaml s3://${aws_s3_bucket.s3_kube_bucket.id}"
    }
}

resource "aws_iam_role" "ssm_ec2_role1" {
  name = "ssm_ec2_role"
  assume_role_policy = file("assume_role_policy.json")
}

resource "aws_iam_role_policy_attachment" "ssm_role_attachment" {
  role       = aws_iam_role.ssm_ec2_role1.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

resource "aws_iam_role_policy_attachment" "ssm_role_attachment2" {
  role       = aws_iam_role.ssm_ec2_role1.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_instance_profile" "ssm_ec2_role_profile" {
  name = "ssm_ec2"
  role = aws_iam_role.ssm_ec2_role1.name
}

resource "aws_instance" "ec2_instance_master" {
  ami = var.ami_id
  subnet_id = aws_subnet.kube_public_subnet.id
  instance_type = var.instance_type
  key_name = var.ami_key_pair_name
  associate_public_ip_address = true
  security_groups = [ aws_security_group.kube_security_group.id ]
  iam_instance_profile = aws_iam_instance_profile.ssm_ec2_role_profile.name
  root_block_device {
    volume_type = "gp2"
    volume_size = "16"
  delete_on_termination = true
  }
  tags = {
    Name = "k8s_master_1"
  }
  user_data_base64 = base64encode("${templatefile("scripts/install_k8s_master.sh", {
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
    region = "${var.region}"
    s3_bucket_name = "${aws_s3_bucket.s3_kube_bucket.id}"
  })}")

  depends_on = [
    aws_s3_bucket.s3_kube_bucket,
    random_string.s3name
  ]
  
} 

resource "aws_instance" "ec2_instance_worker" {
    ami = var.ami_id
    count = var.number_of_worker
    subnet_id = aws_subnet.kube_public_subnet.id
    instance_type = var.instance_type
    key_name = var.ami_key_pair_name
    associate_public_ip_address = true
    security_groups = [ aws_security_group.kube_security_group.id ]
    root_block_device {
      volume_type = "gp2"
      volume_size = "16"
      delete_on_termination = true
    }
    tags = {
        Name = "k8s_worker_${count.index + 1}"
    }
    user_data_base64 = base64encode("${templatefile("scripts/install_k8s_worker.sh", {

      access_key = "${var.access_key}"
      secret_key = "${var.secret_key}"
      region = "${var.region}"
      s3_bucket_name = "${aws_s3_bucket.s3_kube_bucket.id}"
      worker_number = "${count.index + 1}"

    })}")
  
    depends_on = [
      aws_s3_bucket.s3_kube_bucket,
      random_string.s3name,
      aws_instance.ec2_instance_master
  ]
} 