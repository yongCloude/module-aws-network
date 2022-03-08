# Amazon VPC 리소스를 정의 (P176)

## AWS 공급자를 정의
provider "aws" {
  region = var.aws_region
}

## 모듈내에서 사용할 로컬 변수를 선언
## https://www.terraform.io/language/values/locals
locals {
  vpc_name     = "${var.env_name} ${var.vpc_name}"
  cluster_name = "${var.cluster_name}-${var.env_name}"
}

## Amazon VPC를 생성하기 위한 코드를 정의
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
## var.main_vpc_cidr 모듈 재사용을 위해 테라폼 환경변수로 값을 전달
resource "aws_vpc" "main" {
  cidr_block           = var.main_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    "Name"                                        = local.vpc_name,
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}


# 서브넷 정의 (P179)
## 가용영역 정의
## https://www.terraform.io/language/data-sources
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones
data "aws_availability_zones" "available" {
  state = "available"
}

## 퍼블릭 서브넷 정의
resource "aws_subnet" "public-subnet-a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    "Name"                                        = "${local.vpc_name}-public-subnet-a"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_subnet" "public-subnet-b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    "Name"                                        = "${local.vpc_name}-public-subnet-b"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

## 프라이빗 서브넷 정의
resource "aws_subnet" "private-subnet-a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    "Name"                                        = "${local.vpc_name}-private-subnet-a"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_subnet" "private-subnet-b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    "Name"                                        = "${local.vpc_name}-private-subnet-b"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}


# 퍼블릭 서브넷을 위한 인터넷 게이트웨이 및 라우팅 테이블 정의 (P181)
## 인터넷 게이트웨이 정의
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${local.vpc_name}-igw"
  }
}

## 퍼블릭 라우팅 테이블을 정의
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
resource "aws_route_table" "public-route" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${local.vpc_name}-public-route"
  }
}

## 퍼블릭 서브넷과 퍼블릭 라우팅 테이블을 연결
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "public-a-association" {
  route_table_id = aws_route_table.public-route.id
  subnet_id      = aws_subnet.public-subnet-a.id
}

resource "aws_route_table_association" "public-b-association" {
  route_table_id = aws_route_table.public-route.id
  subnet_id      = aws_subnet.public-subnet-b.id
}


# 프라이빗 서브넷을 위한 NAT 게이트웨이를 설정 (P182)
## EIP를 생성해 NAT에 할당
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip
resource "aws_eip" "nat-a" {
  vpc = true
  tags = {
    "Name" = "${local.vpc_name}-NAT-a"
  }
}

resource "aws_eip" "nat-b" {
  vpc = true
  tags = {
    "Name" = "${local.vpc_name}-NAT-b"
  }
}

## NAT 게이트웨이 생성
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway
resource "aws_nat_gateway" "nat-gw-a" {
  allocation_id = aws_eip.nat-a.id
  subnet_id     = aws_subnet.private-subnet-a.id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    "Name" = "${local.vpc_name}-NAT-gw-a"
  }
}

resource "aws_nat_gateway" "nat-gw-b" {
  allocation_id = aws_eip.nat-b.id
  subnet_id     = aws_subnet.private-subnet-b.id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    "Name" = "${local.vpc_name}-NAT-gw-b"
  }
}

# 프라이빗 서브넷에 대한 라우팅을 정의 (P183)
## 프라이빗 라우팅 테이블 정의
resource "aws_route_table" "private-route-a" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gw-a.id
  }
  tags = {
    Name = "${local.vpc_name}-private-route-a"
  }
}

resource "aws_route_table" "private-route-b" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gw-b.id
  }
  tags = {
    Name = "${local.vpc_name}-private-route-b"
  }
}

## 프라이빗 서브넷과 프라이빗 라우팅 테이블을 연결
resource "aws_route_table_association" "private-a-association" {
  route_table_id = aws_route_table.private-route-a.id
  subnet_id      = aws_subnet.private-subnet-a.id
}

resource "aws_route_table_association" "private-b-association" {
  route_table_id = aws_route_table.private-route-b.id
  subnet_id      = aws_subnet.private-subnet-b.id
}
