# AWS Associate Playground

A comprehensive repository for AWS Solution Architect Associate and AWS Developer Associate certification exam preparation using Infrastructure as Code (IaC) and automation tools.

## 🎯 Purpose

This repository serves as a practical learning environment for:
- **AWS Solution Architect Associate** certification preparation
- **AWS Developer Associate** certification preparation
- Hands-on practice with AWS services using modern DevOps tools
- Infrastructure as Code (IaC) implementations
- Automation and configuration management

## 🛠️ Technologies

- **Terraform** - Infrastructure as Code for AWS resource provisioning
- **Ansible** - Configuration management and automation
- **Python** - Scripting, automation, and AWS SDK (Boto3) interactions
- **AWS CLI** - Command-line interface for AWS services

## 📁 Repository Structure

```
aws_associtate_playground/
├── terraform/          # Terraform configurations for AWS resources
├── ansible/            # Ansible playbooks and roles
├── python/             # Python scripts for AWS automation
├── scripts/            # Shell scripts and utilities
├── docs/              # Documentation and study notes
├── examples/          # Example configurations and use cases
└── README.md          # This file
```

## 📋 Prerequisites

### Required Tools
- **AWS Account** - Active AWS account for hands-on practice
- **AWS CLI** - Version 2.x or higher
- **Terraform** - Version 1.0 or higher
- **Ansible** - Version 2.9 or higher
- **Python** - Version 3.8 or higher
- **Git** - For version control

### AWS Credentials Configuration

1. Configure AWS CLI:
   ```bash
   aws configure
   ```

2. Set up credentials:
   - Access Key ID
   - Secret Access Key
   - Default region (e.g., us-east-1)
   - Default output format (json recommended)

## 🚀 Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/skratzsch/aws_associtate_playground.git
cd aws_associtate_playground
```

### 2. Set Up Python Environment
```bash
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Verify Tool Installations
```bash
terraform --version
ansible --version
python --version
aws --version
```

## 💡 Usage

### Terraform Examples
```bash
cd terraform/<example-directory>
terraform init
terraform plan
terraform apply
```

### Ansible Playbooks
```bash
cd ansible
ansible-playbook -i inventory playbook.yml
```

### Python Scripts
```bash
cd python
python script_name.py
```

## 📚 AWS Certification Resources

### AWS Solution Architect Associate
- Focus areas: Compute, Storage, Networking, Databases, Security
- Key services: EC2, S3, VPC, RDS, IAM, CloudFormation, Lambda

### AWS Developer Associate
- Focus areas: Development, Deployment, Security, Troubleshooting
- Key services: Lambda, API Gateway, DynamoDB, SNS, SQS, CodePipeline, CloudWatch

### Recommended Study Materials
- [AWS Documentation](https://docs.aws.amazon.com/)
- [AWS Whitepapers](https://aws.amazon.com/whitepapers/)
- [AWS Free Tier](https://aws.amazon.com/free/)
- [AWS Skill Builder](https://skillbuilder.aws/)

## ⚠️ Important Notes

### Cost Management
- Always clean up resources after practice sessions
- Use `terraform destroy` to remove infrastructure
- Monitor AWS billing dashboard regularly
- Set up billing alerts to avoid unexpected charges

### Security Best Practices
- Never commit AWS credentials to version control
- Use IAM roles and policies with least privilege
- Enable MFA on AWS accounts
- Rotate access keys regularly
- Use AWS Secrets Manager for sensitive data

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:
1. Fork the repository
2. Create a feature branch
3. Make your changes with clear commit messages
4. Test your changes thoroughly
5. Submit a pull request

## 📝 License

This project is intended for educational purposes for AWS certification preparation.

## 🔗 Useful Links

- [AWS Certification](https://aws.amazon.com/certification/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible AWS Modules](https://docs.ansible.com/ansible/latest/collections/amazon/aws/)
- [Boto3 Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html)

## 📧 Contact

For questions or suggestions, please open an issue in this repository.

---

**Happy Learning and Good Luck with your AWS Certifications! 🎓**