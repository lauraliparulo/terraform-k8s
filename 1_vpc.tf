#****** VPC Start ******#

resource "aws_vpc" "kube_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true 
  tags = {
    Name = "K8S VPC"
    #"kubernetes.io/cluster/kubernetes" = "${var.cluster_name}"
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
  #   key   = "kubernetes.io/cluster/${var.cluster_name}"
  }
}

resource "aws_internet_gateway" "kube_internet_gateway" {
  vpc_id = aws_vpc.kube_vpc.id

  tags = {
    Name = "K8S Internet Gateway"
 #   key   = "kubernetes.io/cluster/${var.cluster_name}"
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
 #   Name = "Public Route Table"
    key   = "kubernetes.io/cluster/${var.cluster_name}"
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