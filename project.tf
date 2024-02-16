terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# 1. Create vpc

# 1 references
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags ={
    Name = "production"
  }
}

# 2. Create Internet Gateway
# reference the vpc_id to the resource above: aws_vpc.prod-vpc
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

# 3. Create Custom Route Table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    # egress_only_gateway_id = aws_egress_only_internet_gateway.example.id
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}

# 4. Create a Subnet
resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet"
  }
  
}

# 5. Create subnet with Route Table
resource "aws_route_table_association" "a" {
#   subnet_id      = aws_subnet.foo.id
    subnet_id = aws_subnet.subnet-1.id
#   route_table_id = aws_route_table.bar.id
    route_table_id = aws_route_table.prod-route-table.id
}

# 6. Create Security Group to allow port 22,80,443

# resource "aws_security_group" "sg" {
#   name        = "My Security Group"
#   description = "Basic security group for my VPC."
#   vpc_id      = var.vpc_id

#   ingress {
#     protocol    = "tcp"
#     from_port   = 22
#     to_port     = 22
#     cidr_blocks = ["192.168.1.0/24", "192.168.2.0/24"]
#   }

#   egress {
#     protocol    = "-1"
#     from_port   = 0
#     to_port     = 0
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#   tags = {
#     Name = "My security group"
#     Environment = "Dev"
#   }
# }

# resource "aws_security_group" "allow_tls" {
resource "aws_security_group" "allow_web" {

    # name        = "allow_tls"
    name        = "allow_web_traffic"
    description = "Allow web traffic inbound traffic and all outbound traffic"
    # vpc_id      = aws_vpc.main.id
    vpc_id = aws_vpc.prod-vpc.id
    # tags = {
    #     Name = "allow_tls"
    #     }
    
    ingress {
        description = "SSH"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "HTTP"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "HTTPS"
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    tags = {
        Name = "Allow web"
    }

}

# 7. Create a network interface with an ip in the subnet that was created in step 4
# resource "aws_network_interface" "test" {
resource "aws_network_interface" "web-server-cece" {
#   subnet_id       = aws_subnet.public_a.id
    subnet_id = aws_subnet.subnet-1.id
    # private_ips     = ["10.0.0.50"]
    private_ip = "10.0.1.50"
    # security_groups = [aws_security_group.web.id]
    security_groups = [aws_security_group.allow_web.id]

    # attachment {
    #     instance     = aws_instance.test.id
    #     device_index = 1
    #     }

}
# 8. Assign an elastic IP to the network interface created in step 7

resource "aws_eip" "one" {
    domain                    = "vpc"
#   network_interface         = aws_network_interface.multi-ip.id
    network_interface = aws_network_interface.web-server-cece.id
    # associate_with_private_ip = "10.0.0.10"
    associate_with_private_ip = "10.0.1.85" 
    # If you try to create an EIP, and assing it to a device that's 
#     on a subnet or in a VPC that doesn't have an IGW (internet gate way),
#     it will throw an error 
#     So, for you to have a Public IP address, you need to have an IGW runned first.
#     Terraform can't figure that out on his own.
#     (Check out in the documentation)
#     So we add a depends_on tag
    # depends_on = aws_internet_gateway.gw
    # have to pass it on as list so the [ ] is needed
    depends_on = [ aws_internet_gateway.gw ]
}

# 9. Create Ubuntu server and install/enable apache2
resource "aws_instance" "web-server-instance" {
    ami = "ami-0c7217cdde317cfec"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "llaves"

    network_interface {
        device_index = 0
        network_interface_id = aws_network_interface.web-server-cece.id
    }
# And now guys, this is where the actual magic  happens here. 
# So what we're going to do is   we're going to tell terraform, 
# to on deployment  of this server to actually run a few commands on  
# the server so that we can automatically install  Apache.

# and after sudo bash
# And then finally, this last one's kind  of optional, but what 
# I'm going to do is I'm going to copy some text to the index dot 
# HTML file that gets served by the web server does that we can 
# confirm that, you know,  all of these commands actually worked. 
    user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c "echo your very first web server > /var/www/html/index.html"
                EOF
    tags = {
        Name = "web server"
    }

}