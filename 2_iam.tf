resource "aws_iam_role" "ssm_ec2_role1" {
  name = "ssm_ec2_role"
  assume_role_policy = file("policies/assume_role_policy.json")
}

resource "aws_iam_role_policy_attachment" "ssm_role_attachment" {
  role       = aws_iam_role.ssm_ec2_role1.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

resource "aws_iam_role_policy_attachment" "ssm_role_attachment2" {
  role       = aws_iam_role.ssm_ec2_role1.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

# resource "aws_iam_role_policy_attachment" "ssm_role_attachment3 {
#   role       = aws_iam_role.ssm_ec2_role1.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
# }

resource "aws_iam_instance_profile" "ssm_ec2_role_profile" {
  name = "ssm_ec2"
  role = aws_iam_role.ssm_ec2_role1.name
}
