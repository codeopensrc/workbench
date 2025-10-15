### WARNING - UNSTABLE
Under major refactor from vps to managed kubernetes based infra.  
While under construction, components will change rapidly and unstable.  

TF Modules _may_ end up being actual TF modules but not until much later.  
Another example of things that can change -  
  Currently developing with using single location for `terraform apply` for all infra in mind  
  With increasing number of resources/complexity this philosophy may change  
  (A single apply for everything is neat but not entirely practical at larger scales)  


## Wiki

### [Wiki Link](https://gitlab.codeopensrc.com/os/workbench/-/wikis/home)  

An external Wiki will be available initially with all relevant information to get started. One goal is to integrate/migrate the Wiki into a Docs folder that will live and grow within the repository.  

Wiki will provide a step-by-step guide and information on how to setup a single node or cluster for cloud providers with various pre-installed and pre-configured software for effortless development and deployment.  

## Project Description  
Cloud infrastructure provisioning project using Terraform and Packer.  
Provides ability to create, update, maintain, and migrate cloud infrastructure.  

#### Semi-exhaustive list of software provisioned/provisionable  
- GitLab, Docker, Kubernetes  
- Grafana, Prometheus, Consul  
- Mongo, Redis, Postgres  
- Unity, Mattermost, Nginx, Wekan  

#### Cloud providers currently supported  
- Digital Ocean  
- AWS  

#### Common operations supported  
- DNS, Firewalls, Automatic Backups, Import/Export, S3 Object storage  
- OS/Image snapshots, Service Discovery, System and Application monitoring  
- ChatOps, HTTPS Certificates, GitLab CI/CD, Unity game builds  

#### Forewarning
Due to the rapid development that will introduce breaking changes with each commit it is **not** recommended for production use **unless**  

- Intended purely to bootstrap cluster(s) or node(s)  
- Not intending to pull upstream changes (not recommended long-term)  
- **Very** familiar with Terraform  
- Familiar with software it provisions  

In its current state for those unfamiliar with Terraform, it is intended for development/homelab use to learn and quickly spin up a few nodes and host a test/hobby cluster, website(s), self-hosted git repository, unity build server etc.  

It is currently and will actively continue being used to provision, update, maintain, and migrate a number of **personal** _production_ services and infrastructure.  

[Personal Website](https://www.codeopensrc.com), [Personal GitLab](https://gitlab.codeopensrc.com/explore?sort=latest_activity_desc), [(Private) Mattermost](https://chat.codeopensrc.com/), [(Private) Wekan](https://wekan.codeopensrc.com/)  

