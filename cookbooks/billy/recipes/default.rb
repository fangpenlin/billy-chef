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

# install git
case node[:platform]
when "debian", "ubuntu"
  package "git-core"
else
  package "git"
end

# create billy user
user "billy" do
  comment "user for running Billy system"
  system true
  shell "/bin/false"
end

directory "/usr/local/billy" do
  owner "billy"
  group "billy"
  recursive true
  action :create
end

# clone the billy project for development
git "/usr/local/billy" do
  repository "/vagrant"
  reference "rewrite"
  action :sync
  user "billy"
  group "billy"
end

# create a virtual environment for billy
python_virtualenv "/usr/local/billy/env" do
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
  cwd "/usr/local/billy"
  user "billy"
  group "billy"
  action :run
end

# install billy package
execute "install_billy" do
  command "./env/bin/python setup.py develop"
  cwd "/usr/local/billy"
  creates "billy.egg-info"
  user "billy"
  group "billy"
  action :run
end

# install testing dependencies
execute "install_testing_dependencies" do
  command "./env/bin/pip install -r test_requirements.txt"
  cwd "/usr/local/billy"
  user "billy"
  group "billy"
  action :run
end

# run unit and functional tests
execute "run_unit_functional_tests" do
  command "./env/bin/python setup.py nosetests"
  cwd "/usr/local/billy"
  user "billy"
  group "billy"
  action :run
end

