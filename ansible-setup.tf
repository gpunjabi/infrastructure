variable "keyname" {
  default = "sud"
}
variable "slaves_count" {
  default = "4"
}
variable "key_path" {
  default = "/Users/sudharasan/Downloads/sud.pem"
}
variable "region" {
  default = "us-east-1"
}

provider "aws" {
  region = "${var.region}"
}

data "aws_ami" "AmazonLinux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["137112412989"] # Canonical
}

resource "aws_iam_role" "ansible_role" {
  name = "ansible_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "policy" {
  name        = "ansible_policy"
  path        = "/"
  description = "My test policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ansible_profile" {
  name = "ansible_profile"
  role = "${aws_iam_role.ansible_role.name}"
}

resource "aws_iam_policy_attachment" "attach_policy" {
  name       = "ansible_policy"
  roles      = ["${aws_iam_role.ansible_role.name}"]
  policy_arn = "${aws_iam_policy.policy.arn}"
}

resource "aws_instance" "ansible" {
  ami = "${data.aws_ami.AmazonLinux.id}"

  #subnet_id = "subnet-d1e4a889"
  instance_type          = "t2.micro"
  key_name               = "${var.keyname}"
  vpc_security_group_ids = ["${aws_security_group.ansible.id}"]
  iam_instance_profile   = "${aws_iam_instance_profile.ansible_profile.name}"

  provisioner "remote-exec" {
    inline = [
      "sudo yum install python-pip -y",
      "sudo pip install ansible boto",
      "wget https://raw.githubusercontent.com/ansible/ansible/devel/contrib/inventory/ec2.py",
      "chmod 755 ec2.py",
      "wget https://raw.githubusercontent.com/ansible/ansible/devel/examples/ansible.cfg",
      "sed -i 's/#host_key_checking/host_key_checking/g' ansible.cfg",
      "echo '${join("\n",aws_instance.slaves.*.private_ip)}' > /home/ec2-user/slaves",
    ]

    connection {
      type  = "ssh"
      user  = "ec2-user"
      agent = true
      private_key = "${file(var.key_path)}"
    }
  }

  tags {
    Name        = "Control-Machine"
    ProductName = "DevOps"
  }
}

resource "aws_security_group" "ansible" {
  name        = "ansible"
  description = "Allow all inbound traffic"

  #vpc_id      = "vpc-702df617"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "slaves" {
  ami           = "${data.aws_ami.AmazonLinux.id}"
  instance_type = "t2.micro"

  #subnet_id = "subnet-d1e4a889"
  key_name               = "${var.keyname}"
  vpc_security_group_ids = ["${aws_security_group.ansible.id}"]
  count                  = "${var.slaves_count}"

  tags {
    Name        = "Server-${count.index}"
    ProductName = "DevOps"
  }
}

output "Control" {
  value = "${aws_instance.ansible.public_ip}"
}
