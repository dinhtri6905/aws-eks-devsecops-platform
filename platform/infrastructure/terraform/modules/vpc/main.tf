# Resources created:
#   - VPC
#   - Internet Gateway
#   - Public Subnets  (for ALB, NAT Gateway)
#   - Private Subnets (for EKS Nodes, RDS)
#   - Elastic IPs     (assigned to NAT Gateways)
#   - NAT Gateways
#   - Route Tables    (public + private)
#   - Route Table Associations

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # dev  → single_nat_gateway = true  → 1 NAT Gateway
  # prod → single_nat_gateway = false → 1 NAT Gateway per AZ
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)
}

# ===========================================================
# VPC
# ===========================================================
resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:VPC Flow Logs are intentionally disabled to reduce CloudWatch storage costs in this educational environment.

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"

    # Required tag for EKS and AWS Load Balancer Controller
    # to discover and use this VPC
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ===========================================================
# INTERNET GATEWAY
# ===========================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ===========================================================
# PUBLIC SUBNETS
# Used for: Internet-facing ALB, NAT Gateway
# ===========================================================
resource "aws_subnet" "public" {
  #checkov:skip=CKV_AWS_130:Public subnets intentionally assign public IPs for internet-facing Application Load Balancers in this EKS architecture.

  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Tier = "Public"

    # Tag used by AWS Load Balancer Controller to automatically
    # discover public subnets for internet-facing ALBs
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ===========================================================
# PRIVATE SUBNETS
# Used for: EKS Worker Nodes, RDS
# ===========================================================
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Tier = "Private"

    # Tag used by AWS Load Balancer Controller to automatically
    # discover private subnets for internal ALBs
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ===========================================================
# ELASTIC IPs (Assigned to NAT Gateways)
# ===========================================================
resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  }

  # EIP must be created after the Internet Gateway
  # is attached to the VPC
  depends_on = [aws_internet_gateway.main]
}

# ===========================================================
# NAT GATEWAYS
# ===========================================================
resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name_prefix}-nat-gw-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

# Public Subnet A (10.0.1.0/24)
#                 \
#                  > Public RT
#                 /
# Public Subnet B (10.0.2.0/24)

# Public RT:
# 0.0.0.0/0 → IGW
# ===========================================================
# PUBLIC ROUTE TABLE
# ===========================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ===========================================================
# PRIVATE ROUTE TABLES
# ===========================================================
resource "aws_route_table" "private" {
  count = local.nat_gateway_count

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id = aws_subnet.private[count.index].id

  # dev:  all private subnets use route table [0]
  # prod: subnet[i] uses route table[i] in the same AZ
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}