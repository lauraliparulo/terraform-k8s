#--------S3-------------------
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
        command     = "aws s3 cp k8s/nginx.yaml s3://${aws_s3_bucket.s3_kube_bucket.id}"
    }
}