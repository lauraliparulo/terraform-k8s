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
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
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
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
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