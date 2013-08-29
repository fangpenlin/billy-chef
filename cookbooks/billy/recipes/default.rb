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
include_recipe "postgresql::client"
include_recipe "postgresql::server"
include_recipe "database::postgresql"

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
git node[:billy][:install_dir] do
  repository "/vagrant"
  reference node[:billy][:branch]
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
testing_db_url = "postgresql://"\
      "#{node.billy.testing.db_user}:"\
      "#{node.billy.testing.db_password}"\
      "@localhost/#{node.billy.testing.db}"

execute "run_unit_functional_tests_with_postgresql" do
  command "./env/bin/python setup.py nosetests"
  cwd "#{node.billy.install_dir}"
  environment ({
    'BILLY_UNIT_TEST_DB' => testing_db_url, 
    'BILLY_FUNC_TEST_DB' => testing_db_url
  })
  user "billy"
  group "billy"
  action :run
end

