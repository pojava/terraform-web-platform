# 🌐 Terraform Web Platform

A **modular, production-ready web application infrastructure** built with Terraform.  
This project provisions a **multi-environment setup (dev & prod)** with best practices for scalability, security, and maintainability.  

---

## 🚀 Features

- **Multi-Environment**: Separate `dev` and `prod` environments with isolated state.
- **Modular Design**: Reusable Terraform modules for networking, compute, database, and monitoring.
- **High Availability**: Multi-AZ VPC, private/public subnets, and NAT gateways.
- **Auto Scaling**: Application Load Balancer (ALB) + EC2 Auto Scaling Group.
- **Managed Database**: RDS MySQL with backups and maintenance windows.
- **Monitoring & Alerts**: CloudWatch metrics and alarms for proactive monitoring.
- **Version-Controlled Infrastructure**: Git + Terraform workflow for safe deployments.

---

## 📂 Project Structure

```plaintext
terraform-web-platform/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── outputs.tf
│   └── prod/
│       ├── main.tf
│       ├── terraform.tfvars
│       └── outputs.tf
├── modules/
│   ├── networking/
│   ├── compute/
│   ├── database/
│   └── monitoring/
├── bootstrap/
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars.example
├── README.md
└── .gitignore
```

---

## 🛠️ Setup Instructions

### 1️⃣ Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.5
- [AWS CLI](https://aws.amazon.com/cli/) configured with `aws configure`
- Git installed
- An AWS account with permissions to create VPC, EC2, RDS, IAM, and CloudWatch resources.

---

### 2️⃣ Bootstrap Backend
Provision the Terraform S3 bucket and DynamoDB table for remote state locking:
```bash
cd bootstrap
terraform init
terraform apply
```

---

### 3️⃣ Deploy Environment
Choose your environment (dev or prod):
```bash
cd environments/dev    # or environments/prod
terraform init
terraform plan
terraform apply
```

---

## 🔒 Security Best Practices
- `.terraform/`, `*.tfstate`, and `terraform.tfvars` are **ignored** via `.gitignore`.
- Secrets and credentials are **never stored in Git**.
- [git-secrets](https://github.com/awslabs/git-secrets) is configured to scan commits:
  ```bash
  git secrets --scan
  ```
- Rotate any exposed credentials immediately.

---

## 🧹 Cleanup
To avoid AWS costs:
```bash
terraform destroy
```

---

## 📝 Roadmap
- [ ] Add CI/CD (GitHub Actions)
- [ ] Add container orchestration (ECS or EKS)
- [ ] Add automated tests for Terraform code
- [ ] Add cost monitoring with AWS Budgets

---

## 📜 License
This project is licensed under the [MIT License](LICENSE).

---

## 🙌 Contributions
Pull requests and suggestions are welcome!  
Please open an issue if you find a bug or want to request a feature.
