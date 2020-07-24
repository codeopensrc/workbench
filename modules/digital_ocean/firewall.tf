
##### How firewalls were done in UFW for linux machines before AWS security groups
##### Written as a chef recipe using ruby
##### Below is the json data structure that was used
# {
#     "id": "ips",
#     "app_ips": [
#         {"do1": ""},
#         {"aws1": ""},
#     ],
#     "station_ips": [
#         {"station1": ""},
#         {"station2": ""},
#         {"station3": ""}
#     ],
#     "docker_subnets": [ "172.16.0.0/12", "192.168.0.0/20" ]
# }

####node cookbook
##### Firewall #####
# firewall_rule 'http/https/docker' do
#     port [80, 443, 2377, 7946]
#     protocol :tcp
# end
#
# firewall_rule 'docker udp' do
#     port [7946, 4789]
#     protocol :udp
# end

# ips_json = JSON.parse(::File::read("/root/code/access/ips.json"))
#
# ips_json['docker_subnets'].each do |ip|
#     firewall_rule "Allow from #{ip}" do
#         source ip
#     end
# end






######mongo cookbook
##### Firewall #####
# ips_json = JSON.parse(::File::read("/root/code/access/ips.json"))
#
# ips_json['app_ips'].each do |ipObj|
#     ipObj.each do |tag, ip|
#         firewall_rule "allow #{tag}" do
#             source ip
#             port 27017
#             protocol :tcp
#         end
#     end
# end
#
# managers = search(:node, 'role:manager')
# webs = search(:node, 'role:web')
# mongos = search(:node, 'role:db_mongo')
# dbs = search(:node, 'role:db')
# nodes = managers + webs + mongos + dbs
#
# nodes.each do |node|
#     ip = ""
#     if node.attribute?('ec2')
#         ip = node['ec2']['public_ipv4']
#     else
#         # t3a ec2 instance had the inet interface at ens5 instead of eth0
#         ip = node[:network][:interfaces][:eth0]['addresses'].detect{|k,v| v[:family] == 'inet'}.first
#     end
#     firewall_rule "Allow from #{ip}" do
#         source ip
#         port 27017
#         protocol :tcp
#     end
# end






##### build cookbook
###### Firewall - Only does docker? TODO: Do this better #####
# ips_json = JSON.parse(::File::read("/root/code/access/ips.json"))
#
# ips_json['docker_subnets'].each do |ip|
#     firewall_rule "Allow from #{ip}" do
#         source ip
#     end
# end





#####pg cookbook
##### Firewall #####
# ips_json = JSON.parse(::File::read("/root/code/access/ips.json"))
#
# ips_json['app_ips'].each do |ipObj|
#     ipObj.each do |tag, ip|
#         firewall_rule "allow #{tag}" do
#             source ip
#             port 5432
#             protocol :tcp
#         end
#     end
# end
#
#
# managers = search(:node, 'role:manager')
# webs = search(:node, 'role:web')
# pgs = search(:node, 'role:db_pg')
# dbs = search(:node, 'role:db')
# nodes = managers + webs + pgs + dbs
#
# nodes.each do |node|
#     ip = ""
#     if node.attribute?('ec2')
#         ip = node['ec2']['public_ipv4']
#     else
#         # t3a ec2 instance had the inet interface at ens5 instead of eth0
#         ip = node[:network][:interfaces][:eth0]['addresses'].detect{|k,v| v[:family] == 'inet'}.first
#     end
#     firewall_rule "Allow from #{ip}" do
#         source ip
#         port 5432
#         protocol :tcp
#     end
# end














######redis cookbook
##### Firewall #####
# ips_json = JSON.parse(::File::read("/root/code/access/ips.json"))
#
# ips_json['app_ips'].each do |ipObj|
#     ipObj.each do |tag, ip|
#         firewall_rule "allow #{tag}" do
#             source ip
#             port 6379
#             protocol :tcp
#         end
#     end
# end


# managers = search(:node, 'role:manager')
# webs = search(:node, 'role:web')
# redis = search(:node, 'role:db_redis')
# dbs = search(:node, 'role:db')
# nodes = managers + webs + redis + dbs
#
# nodes.each do |node|
#     ip = ""
#     if node.attribute?('ec2')
#         ip = node['ec2']['public_ipv4']
#     else
#         # t3a ec2 instance had the inet interface at ens5 instead of eth0
#         ip = node[:network][:interfaces][:eth0]['addresses'].detect{|k,v| v[:family] == 'inet'}.first
#     end
#     firewall_rule "Allow from #{ip}" do
#         source ip
#         port 6379
#         protocol :tcp
#     end
# end













##### trusty cookbook
# firewall 'default' do
#     action :install
# end
#
# firewall_rule 'ssh' do
#     port 22
#     protocol :tcp
# end


#### TODO: This is where we come up with a better solution
# ips_json = JSON.parse(::File::read("/root/code/access/ips.json"))
#
# ips_json['station_ips'].each do |ipObj|
#     ipObj.each do |tag, ip|
#         firewall_rule "allow #{tag}" do
#             source ip
#         end
#     end
# end


#### Consul
# managers = search(:node, 'role:manager')
# webs = search(:node, 'role:web')
# builds = search(:node, 'role:build')
# mongos = search(:node, 'role:db_mongo')
# pgs = search(:node, 'role:db_pg')
# redis = search(:node, 'role:db_redis')
# dbs = search(:node, 'role:db')
# admin = search(:node, 'role:admin')
# nodes = managers + webs + builds + mongos + pgs + redis + dbs + admin
#
#
# nodes.each do |node|
#     ip = ""
#     if node.attribute?('ec2')
#         ip = node['ec2']['public_ipv4']
#     else
#         # t3a ec2 instance had the inet interface at ens5 instead of eth0
#         ip = node[:network][:interfaces][:eth0]['addresses'].detect{|k,v| v[:family] == 'inet'}.first
#     end
#     firewall_rule "Allow from #{ip}" do
#         source ip
#         port [8600, 8500, 8400, 8301, 8302, 8300]
#         protocol :tcp
#     end
# end




##### trusty/admin recipe
### Firewall
# firewall_rule 'chef_server' do
#     port [80, 443, 7080]
#     protocol :tcp
# end







# Allowing specific ip addresses in
# provisioner "file" {
#     content = fileexists("${path.module}/template_files/ignore/ips.json") ? file("${path.module}/template_files/ignore/ips.json") : ""
#     destination = "/root/code/access/ips.json"
# }
