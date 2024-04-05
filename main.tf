resource "aws_vpc" "mtc_vpc" {
  cidr_block           = "10.123.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "dev"
  }
}

resource "aws_subnet" "mtc_public_subnet" {
  # reference to a resource
  vpc_id                  = aws_vpc.mtc_vpc.id
  cidr_block              = "10.123.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-1a"

  tags = {
    name = "dev-public"
  }
}

resource "aws_internet_gateway" "mtc_internet_gateway" {
  vpc_id = aws_vpc.mtc_vpc.id

  tags = {
    Name = "dev-igw"
  }
}

# Route table is going to route traffic from the internet gateway to the subnet
resource "aws_route_table" "mtc_public_rt" {
  vpc_id = aws_vpc.mtc_vpc.id


  tags = {
    Name = "dev_public_rt"
  }
}

resource "aws_route" "default_route" {
  route_table_id = aws_route_table.mtc_public_rt.id
  # this cidr block allows all traffic
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.mtc_internet_gateway.id

}


resource "aws_route_table_association" "mtc_public__rt_association" {
  subnet_id      = aws_subnet.mtc_public_subnet.id
  route_table_id = aws_route_table.mtc_public_rt.id
}

resource "aws_security_group" "mtc_sg" {
  name        = "dev_sg"
  description = "dev security group"
  vpc_id      = aws_vpc.mtc_vpc.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    #/32 is used to identify a route to a specific IP host address. only denotes one IP address
    cidr_blocks = ["98.45.29.172/32"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_key_pair" "mtc_auth" {
  key_name = "mtcKey"
  # using a tf function so don't need to ent the entire key
  public_key = file("~/.ssh/mtcKey.pub")
}

resource "aws_instance" "dev_node" {
  instance_type          = "t2.micro"
  ami                    = data.aws_ami.server_ami.id
  key_name               = aws_key_pair.mtc_auth.id
  vpc_security_group_ids = [aws_security_group.mtc_sg.id]
  subnet_id              = aws_subnet.mtc_public_subnet.id
  # this will extract the userdata file and bootstrap the instance 
  user_data = file("userdata.tpl")

  tags = {
    Name = "dev-node"

  }


  root_block_device {
    volume_size = 10
  }

  #provisioner is used to manage our local configuration. always used in another resource
  provisioner "local-exec" {
    # this will cause for a value to be entered when the a plan or apply is executed
    command = templatefile("${var.host_os}-ssh-config.tpl", {
      hostname = self.public_ip
      #ec2 user provider name
      user         = "ubuntu"
      identityfile = "~/.ssh/mtcKey"
    })
    interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }

}