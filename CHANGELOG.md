
# 0.2.0 - (*2022-11-20*)

### Notable changes  
### 0.1.0 -> 0.2.0

Version 0.2.0 is obviously a massive overhaul with far more changes than the changelog indidicates from 0.1.0.
This is due to several factors and not doing any type of regular releases.

Development is rather ad-hoc and small updates but with the huge upgrade from gitlab and kubernetes, a minor 
release feels appropriate.

Going forward and as the project matures, the CHANGELOG.md will play a more important role.

That being said, some notable things below with many unlisted:

- Convert 95+% script based provisioning into ansible
- Upgrade to ubuntu lts 22.04 for Digital Ocean
- Upgrade gitlab to 15.5.3
- Upgrade kubernetes to 1.24.7
- Deprecate shell runners except for build servers
- Deprecate cert-based gitlab integration for agent-based integration
- Add Digital Ocean cloud volume support
  - AWS will be soon to follow, Azure eventually
- Add buildkitd pod for in-cluster docker builds
- Add helm, skaffold, and buildctl to gitlab k8s runner image
- Add basic azure support
- Add mongoDB clustering logic
  - All databases will soon be project/container based however
- Add alpha stage implentation for managed_kubernetes 

Planned deprecations
- Docker swarm will no longer be supported and removed very soon
- No more shell runners period, converting all to k8s runners
- Databases will be container based and not installed on the machine

<br>

#### **Massive (1)**
- [ [85c5cd5](https://gitlab.codeopensrc.com/os/workbench/-/commit/85c5cd5) ] **`massive`** - Upgrade ubuntu img, gitlab, kubernetes, docker etc [#37](https://gitlab.codeopensrc.com/os/workbench/-/issues/37)  

#### **Changed (1)**
- [ [22163a9](https://gitlab.codeopensrc.com/os/workbench/-/commit/22163a9) ] **`changed, deprecated`** - General updates, fixes, and notes  

