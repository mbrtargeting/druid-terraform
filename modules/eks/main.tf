module "eks-terraform" {
  source       = "terraform-aws-modules/eks/aws"
  version      = "4.0.2"
  cluster_name = "${var.cluster_name}"

  # Deploy in all possible networks. EKS cannot be changed afterwards
  vpc_id  = "${var.vpc_id}"
  subnets = ["${var.private_subnets}", "${var.public_subnets}"]

  manage_aws_auth = true
  cluster_version = "1.12"

  worker_groups = [
    {
      instance_type        = "${var.instance_type}"
      key_name             = "${var.key_name}"
      asg_desired_capacity = "${var.desired_capacity}"
      asg_min_size         = "${var.min_size}"
      asg_max_size         = "${var.max_size}"
      autoscaling_enabled  = true

      # Workers are only deployed on the private networks for now      
      subnets = "${join(",", var.private_subnets)}"
    },
  ]

  # Add ssh access
  worker_additional_security_group_ids = ["${aws_security_group.allow_workers_ssh.id}"]

  tags = "${var.tags}"
}

# Allow ssh access
resource "aws_security_group" "allow_workers_ssh" {
  name_prefix = "${var.cluster_name}"
  description = "Allow SSH inbound traffic"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a explicit dependency so that starts once it is ready
# It is required to be able to execute kubectl
resource "null_resource" "update_eks_config" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks-terraform.cluster_id}"
  }
}

resource "kubernetes_service_account" "eks-admin" {
  metadata {
    name      = "${var.name}"
    namespace = "${var.namespace}"
  }

  automount_service_account_token = true
}

resource "kubernetes_cluster_role_binding" "eks-admin" {
  metadata {
    name = "${kubernetes_service_account.eks-admin.metadata.0.name}"
  }

  role_ref {
    kind      = "ClusterRole"
    name      = "cluster-admin"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "${kubernetes_service_account.eks-admin.metadata.0.name}"
    namespace = "${kubernetes_service_account.eks-admin.metadata.0.namespace}"
    api_group = ""
  }
}