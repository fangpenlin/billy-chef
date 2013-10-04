#
# Cookbook Name:: billy
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

include_recipe "apt"
include_recipe "python"
include_recipe "nginx::source"
include_recipe "postgresql::client"
include_recipe "postgresql::server"
include_recipe "database::postgresql"

# set the file descriptor number limitations
template "/etc/security/limits.conf" do
  source "limits.conf.erb"
  owner "root"
  group "root"
end

# TODO: what about some security setup? fail2ban?

postgresql_connection_info = {:host => "127.0.0.1",
                              :port => node['postgresql']['config']['port'],
                              :username => 'postgres',
                              :password => node['postgresql']['password']['postgres']}

# create a testing account
postgresql_database_user node[:billy][:testing][:db_user] do
  connection postgresql_connection_info
  password node[:billy][:testing][:db_password]
  action :create
end

# create a testing account
postgresql_database node[:billy][:testing][:db] do
  connection postgresql_connection_info
  owner node[:billy][:testing][:db_user]
  action :create
end

# create a production account
postgresql_database_user node[:billy][:prod][:db_user] do
  connection postgresql_connection_info
  password node[:billy][:prod][:db_password]
  action :create
end

# create a production account
postgresql_database node[:billy][:prod][:db] do
  connection postgresql_connection_info
  owner node[:billy][:prod][:db_user]
  action :create
end

# install git
case node[:platform]
when "debian", "ubuntu"
  package "git-core"
else
  package "git"
end

# create billy user
user node[:billy][:user] do
  supports :manage_home => true
  comment "user for running Billy system"
  home "/home/#{node.billy.user}"
  shell "/bin/bash"
end

directory node[:billy][:install_dir] do
  owner "billy"
  group "billy"
  recursive true
  action :create
end

# clone the billy project for development
# TODO: clone from github if we are not in vagrant environment?
git node[:billy][:install_dir] do
  repository node[:billy][:git_repo]
  reference node[:billy][:git_branch]
  action :sync
  user "billy"
  group "billy"
end

# create a virtual environment for billy
python_virtualenv "#{node.billy.install_dir}/env" do
  owner "billy"
  group "billy"
  options "--no-site-packages"
  action :create
end

# install distribute
# hum... strange, distribute is not installed in virtualenv
# we created above, so we need to install it here manually
execute "install_distribute" do
  command "./env/bin/python distribute_setup.py"
  cwd "#{node.billy.install_dir}"
  user "billy"
  group "billy"
  action :run
end

# install billy package
execute "install_billy" do
  command "./env/bin/python setup.py develop"
  cwd "#{node.billy.install_dir}"
  creates "billy.egg-info"
  user "billy"
  group "billy"
  action :run
end

# install PostgreSQL driver for python
python_pip "psycopg2" do
  virtualenv "#{node.billy.install_dir}/env"
end

# install testing dependencies
execute "install_testing_dependencies" do
  command "./env/bin/pip install -r test_requirements.txt"
  cwd "#{node.billy.install_dir}"
  user "billy"
  group "billy"
  action :run
end

# run unit and functional tests
execute "run_unit_functional_tests" do
  command "./env/bin/python setup.py nosetests"
  cwd "#{node.billy.install_dir}"
  user "billy"
  group "billy"
  action :run
end

# run unit and functional tests on postgresql
execute "run_unit_functional_tests_with_postgresql" do
  command "./env/bin/python setup.py nosetests"
  cwd node[:billy][:install_dir]
  environment ({
    'BILLY_UNIT_TEST_DB' => node[:billy][:testing][:db_url], 
    'BILLY_FUNC_TEST_DB' => node[:billy][:testing][:db_url]
  })
  user "billy"
  group "billy"
  action :run
end

# prepare the environment for running billy
###########################################

# generate a self signed key and crt, should be replaced manually later
# if this is going to be a production environment
bash "openvpn-server-key" do
  environment("KEY_CN" => "server")
  code <<-EOF
    openssl req -x509 -batch -days 3650 \
      -nodes -new -newkey rsa:2048 -keyout #{ node[:billy][:ssl][:key_path] } \
      -out #{ node[:billy][:ssl][:crt_path] }
  EOF
  not_if { ::File.exists?(node[:billy][:ssl][:crt_path]) }
end

# install supervisord
python_pip "supervisor"
# install uwsgi for our env
python_pip "uwsgi" do
  virtualenv "#{ node.billy.install_dir }/env"
end
# create logs folder
directory "/home/#{ node.billy.user }/logs" do
  owner "billy"
  group "billy"
  recursive true
  action :create
end
# create files from template
[ 
  [ "/home/#{ node.billy.user }/supervisord.conf", 'supervisord.conf.erb' ],
  [ "#{ node.billy.install_dir }/web.sd.conf", 'web.sd.conf.erb' ],
  [ "#{ node.billy.install_dir }/prod.ini", 'prod.ini.erb' ],
  [ "#{ node.billy.install_dir }/wsgi.py", 'wsgi.py.erb' ],
  [ "#{ node.billy.install_dir }/web.nx.conf", 'web.nx.conf.erb' ],
].each do |dest_file, tmpl_source|
  template dest_file do
    source tmpl_source
    owner "billy"
    group "billy"
  end
end
# link nginx configure
link "#{ node.nginx.dir }/sites-enabled/billy_web.conf" do
  to "#{ node.billy.install_dir }/web.nx.conf"
  owner 'root'
  notifies :reload, 'service[nginx]'
end
# initialize the database
execute "initialize_database" do
  command "./env/bin/initialize_billy_db prod.ini"
  cwd node[:billy][:install_dir]
  user "billy"
  group "billy"
  action :run
end
# setup crontab for running process transactions
cron "process_transactions" do
  command "cd #{ node.billy.install_dir } && "\
    "./env/bin/process_billy_tx prod.ini >> "\
    "/home/#{ node.billy.user }/logs/cron_process_transactions.log 2>&1 "
  minute "*/3"
  hour "*"
  day "*"
  month "*"
  weekday "*"
  user "billy"
  action :create
end
# setup supervisord service
template "/etc/init.d/supervisord" do
  source "supervisord.erb"
  owner "root"
  group "root"
  mode "0755"
  notifies :enable, "service[supervisord]"
  notifies :start, "service[supervisord]"
end
service "supervisord" do
  supports :status => true, :restart => true, :reload => true
  action [:enable, :restart]
end
