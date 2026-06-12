# VPC Module

Terraform module for provisioning an AWS VPC for EKS and cloud-native workloads.

## Features

* VPC with configurable CIDR block
* Public and Private Subnets across multiple AZs
* Internet Gateway
* NAT Gateway (single or per-AZ)
* Route Tables and Associations
* EKS-compatible subnet tagging

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project_name       = "eks-devsecops"
  environment        = "dev"
  vpc_cidr           = "10.0.0.0/16"
  single_nat_gateway = true

  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

  availability_zones = [
    "ap-southeast-1a",
    "ap-southeast-1b"
  ]
}
```

## Inputs

| Name                 | Description                      |
| -------------------- | -------------------------------- |
| project_name         | Project name                     |
| environment          | Environment (dev/prod)           |
| vpc_cidr             | VPC CIDR block                   |
| public_subnet_cidrs  | Public subnet CIDRs              |
| private_subnet_cidrs | Private subnet CIDRs             |
| availability_zones   | Availability Zones               |
| single_nat_gateway   | Single NAT Gateway or one per AZ |

## Outputs

* `vpc_id`
* `public_subnet_ids`
* `private_subnet_ids`
* `nat_gateway_ids`
* `public_route_table_id`
* `private_route_table_ids`

## Notes

* `single_nat_gateway = true` → Cost-optimized (Dev)
* `single_nat_gateway = false` → High Availability (Prod)
* Includes required subnet tags for Amazon EKS and AWS Load Balancer Controller.
