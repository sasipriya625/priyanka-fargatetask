#variables
variable "subnet_cidrs_public" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
  type = list
}
variable "subnet_cidrs_private" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
  type = list
}
variable "availability_zones" {
  default = ["us-east-1a", "us-east-1b"]
}
data "aws_iam_role" "iam" {
  name = "codedeployforECS-BG"
}
#code
resource "aws_vpc" "vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "vpc"
  }
}
resource "aws_subnet" "publicsubnets" {
  count = length(var.subnet_cidrs_public)
  vpc_id     = aws_vpc.vpc.id
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = "true"
  cidr_block = var.subnet_cidrs_public[count.index]
    tags = {
      Name = format("PublicpriyaFargate-%g",count.index)
   }
}
resource "aws_subnet" "private_subnet1" {
    vpc_id     = aws_vpc.vpc.id
    availability_zone = var.availability_zones[0]
    map_public_ip_on_launch = "false"
    cidr_block = var.subnet_cidrs_private[0]
    tags = {
        Name = format("PrivatePriyaFargate-%g",1)
    }
}
resource "aws_subnet" "private_subnet2" {
    vpc_id     = aws_vpc.vpc.id
    availability_zone = var.availability_zones[1]
    map_public_ip_on_launch = "false"
    cidr_block = var.subnet_cidrs_private[1]
    tags = {
        Name = format("PrivatePriyaFargate-%g",2)
    }
}
resource "aws_eip" "elasticip"{
  vpc = true
  depends_on = [aws_internet_gateway.priyaigw]
}
resource "aws_internet_gateway" "priyaigw" {
  vpc_id = aws_vpc.vpc.id
}
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.elasticip.id
  subnet_id = aws_subnet.publicsubnets[0].id
  
  tags = {
    Name = "Natgw"
  }
}
resource "aws_route_table" "publicRT1" {
    vpc_id = aws_vpc.vpc.id  
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.priyaigw.id
    }
    tags = {
      Name = "PriyaPublicRoute"
    }
}
resource "aws_route_table" "privateRT2" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    Name = "PriyaRouteFargate"
  }
}
resource "aws_route_table_association" "RTA1" {
  count = length(var.subnet_cidrs_public)
  subnet_id      = element(aws_subnet.publicsubnets.*.id, count.index)
  route_table_id = aws_route_table.publicRT1.id
}
resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private_subnet1.id
  route_table_id = aws_route_table.privateRT2.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private_subnet2.id
  route_table_id = aws_route_table.privateRT2.id
}
resource "aws_security_group" "priya-security-group" {
  name        = "priya_security_group"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.vpc.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "priya_security_group"
  }
}
resource "aws_lb_target_group" "priya_target_group_1" {
  name     = "priya-target-group-1"
  port     = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_vpc.vpc.id
  # Alter the destination of the health check to be the login page.
  health_check {    
    healthy_threshold   = 3    
    unhealthy_threshold = 10    
    timeout             = 5    
    interval            = 10    
    path                = "/"    
    port                = "80"  
  }
}
resource "aws_lb_target_group" "priya_target_group_2" {
  name     = "priya-target-group-2"
  port     = 8080
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_vpc.vpc.id
  # Alter the destination of the health check to be the login page.
  health_check {    
    healthy_threshold   = 3    
    unhealthy_threshold = 10    
    timeout             = 5    
    interval            = 10    
    path                = "/"    
    port                = "80"  
  }
}
resource "aws_lb" "alb" {
  name            = "alb"
  security_groups = [aws_security_group.ssg2.id]
  subnets         = [for subnet in aws_subnet.publicsubnets : subnet.id]
  tags = {
    Name = "alb"
  }
}
output "ip-address" {
  value = aws_lb.alb.dns_name
}
resource "aws_lb_listener" "alb_listener_1" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.priya_target_group_1.arn
  }
}
resource "aws_lb_listener" "alb_listener_2" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "8080"
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.priya_target_group_2.arn
  }
}
resource "aws_ecr_repository" "priya-image"{
  name                 = "ecrpriyafargate"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
resource "aws_ecr_repository_policy" "demo-repo-policy" {
  repository = "priyanka"
  policy     = <<EOF
  {
    "Version": "2008-10-17",
    "Statement": [
      {
        "Sid": "adds full ecr access to the demo repository",
        "Effect": "Allow",
        "Principal": "*",
        "Action": [
          "ecr:*",
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetLifecyclePolicy",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
      }
    ]
  }
  EOF
}

resource "aws_ecs_cluster" "sasi-cluster" {
  name = "PriyaFargateCluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
resource "aws_ecs_task_definition" "task_definition" {
family  = "service"
requires_compatibilities = ["FARGATE"]
network_mode = "awsvpc"
cpu = 1024
memory  = 2048
execution_role_arn = data.aws_iam_role.iam.arn
 container_definitions = file("./service.json")
}
resource "aws_security_group" "ssg2" {
  name        = "priyasg"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups  = [aws_security_group.priya-security-group.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "priyafargatesg"
  }
}

resource "aws_ecs_service" "ecs" {
  name                 = "SasiFargate-ecs"
  cluster              = aws_ecs_cluster.sasi-cluster.id
  task_definition      = aws_ecs_task_definition.task_definition.arn
  desired_count        = 2
  force_new_deployment = true
   launch_type     = "FARGATE"
  network_configuration {
    security_groups  = [aws_security_group.ssg2.id]
    subnets          = [aws_subnet.private_subnet1.id, aws_subnet.private_subnet2.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.priya_target_group_1.arn
    container_name   = "priyaFragateContainer"
    container_port   = 80
  }
}
  # ordered_placement_strategy {
  #   type  = "spread"
  #   field = "cpu"
  # }
  resource "aws_codedeploy_app" "codedeploy_ss" {
  compute_platform = "ECS"
  name             = "codedeploy-ss"
  }
  resource "aws_codedeploy_deployment_group" "codedeployment_ss" {
  app_name               = "aws_codedeploy_app.codedeploy_ss.name"
  deployment_group_name  = "codedeployment-ss"
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  service_role_arn       = data.aws_iam_role.iam.arn
  
  # auto_rollback_configuration {
  #   enabled = "true"
  #   events = ["DEPLOYMENT_FAILURE"]
  # }
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
  terminate_blue_instances_on_deployment_success {
    action = "TERMINATE"
    termination_wait_time_in_minutes = 5
    }
  }
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  ecs_service {
    cluster_name = aws_ecs_cluster.sasi-cluster.name
    service_name = aws_ecs_service.ecs.name
  }
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.alb_listener_1.arn]
      }
      target_group {
        name = "aws_lb_target_group.priya_target_group_1.name"
      }

      target_group {
        name = "aws_lb_target_group.priya_target_group_2.name"
      }
      test_traffic_route {
        listener_arns = [aws_lb_listener.alb_listener_2.arn]
      }
    }
  }
  }
  
/*resource "aws_iam_role" "default" {
  name               = "${local.iam_name}"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
  path               = "${var.iam_path}"
  description        = "${var.description}"
  tags               = "${merge(map("Name", local.iam_name), var.tags)}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}
resource "aws_iam_policy" "default" {
  name        = "${local.iam_name}"
  policy      = "${data.aws_iam_policy_document.policy.json}"
  path        = "${var.iam_path}"
  description = "${var.description}"
}
data "aws_iam_policy_document" "policy" {
  statement {
    effect = "Allow"

    actions = [
      "iam:PassRole",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ecs:DescribeServices",
      "ecs:CreateTaskSet",
      "ecs:UpdateServicePrimaryTaskSet",
      "ecs:DeleteTaskSet",
      "cloudwatch:DescribeAlarms",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "sns:Publish",
    ]

    resources = ["arn:aws:sns:*:*:CodeDeployTopic_*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:ModifyRule",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction",
    ]

    resources = ["arn:aws:lambda:*:*:function:CodeDeployHook_*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectMetadata",
      "s3:GetObjectVersion",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:ExistingObjectTag/UseWithCodeDeploy"
      values   = ["true"]
    }

    resources = ["*"]
  }
}

# https://www.terraform.io/docs/providers/aws/r/iam_role_policy_attachment.html
resource "aws_iam_role_policy_attachment" "default" {
  role       = "${aws_iam_role.default.name}"
  policy_arn = "${aws_iam_policy.default.arn}"
}

locals {
  iam_name = "${var.name}-ecs-codedeploy"
}*/
/*resource "aws_ecs_service" "ecs" {
  name                 = "SasiFargate-ecs"
  cluster              = "aws_ecs_cluster.sasi-cluster.id"
  task_definition      = "aws_ecs_task_definition.task_definition.arn"
  desired_count        = 2
  force_new_deployment = true
   launch_type     = "FARGATE"*/

  

resource "aws_route53_zone" "Priyaroute" {
  name = "priyaroute.tk"
  vpc {
    vpc_id = aws_vpc.vpc.id       
  }

  lifecycle {
   ignore_changes = [vpc]
  }
}
resource "aws_route53_record" "priyarecord" {
  zone_id = aws_route53_zone.Priyaroute.zone_id
  name    = "priyaroute.tk"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

/*resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.Priyaroute.zone_id
  name    = "www.route.tk"
  type    = "A"
  ttl     = 300
  records = [aws_eip.lb.public_ip]
}*/

/*resource "aws_route53_zone_association" "Route53_association1" {
  zone_id = aws_route53_zone.Priya_route.id
}*/
