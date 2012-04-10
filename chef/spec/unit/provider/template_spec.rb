#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'stringio'
require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))

describe Chef::Provider::Template do
  before(:each) do
    @cookbook_repo = File.expand_path(File.join(CHEF_SPEC_DATA, "cookbooks"))
    Chef::Cookbook::FileVendor.on_create { |manifest| Chef::Cookbook::FileSystemFileVendor.new(manifest, @cookbook_repo) }

    @node = Chef::Node.new
    @cookbook_collection = Chef::CookbookCollection.new(Chef::CookbookLoader.new(@cookbook_repo))
    @run_context = Chef::RunContext.new(@node, @cookbook_collection)

    @rendered_file_location = Dir.tmpdir + '/openldap_stuff.conf'

    @resource = Chef::Resource::Template.new(@rendered_file_location)
    @resource.cookbook_name = 'openldap'

    @provider = Chef::Provider::Template.new(@resource, @run_context)
    @current_resource = @resource.dup
    @provider.current_resource = @current_resource
  end

  describe "when creating the template" do

    after do
      FileUtils.rm(@rendered_file_location) if ::File.exist?(@rendered_file_location)
    end

    it "finds the template file in the coobook cache if it isn't local" do
      @provider.template_location.should == CHEF_SPEC_DATA + '/cookbooks/openldap/templates/default/openldap_stuff.conf.erb'
    end

    it "finds the template file locally if it is local" do
      @resource.local(true)
      @resource.source('/tmp/its_on_disk.erb')
      @provider.template_location.should == '/tmp/its_on_disk.erb'
    end

    it "should use the cookbook name if defined in the template resource" do
      @resource.cookbook_name = 'apache2'
      @resource.cookbook('openldap')
      @resource.source "test.erb"
      @provider.template_location.should == CHEF_SPEC_DATA + '/cookbooks/openldap/templates/default/test.erb'
    end

    describe "when the target file does not exist" do
      it "creates the template with the rendered content" do
        @node[:slappiness] = "a warm gun"
        @provider.should_receive(:backup)
        @provider.run_action(:create)
        IO.read(@rendered_file_location).should == "slappiness is a warm gun"
        @resource.should be_updated_by_last_action
      end

      it "should set the file access control as specified in the resource" do
        @resource.owner("adam")
        @resource.group("wheel")
        @resource.mode(00644)
        @provider.should_receive(:set_all_access_controls) 
        @provider.run_action(:create)
        @resource.should be_updated_by_last_action
      end

      it "creates the template with the rendered content for the create if missing action" do
        @node[:slappiness] = "happiness"
        @provider.should_receive(:backup)
        @provider.run_action(:create_if_missing)
        IO.read(@rendered_file_location).should == "slappiness is happiness"
        @resource.should be_updated_by_last_action
      end
    end

    describe "when the target file has the wrong content" do
      before do
        File.open(@rendered_file_location, "w+") { |f| f.print "blargh" }
      end

      it "overwrites the file with the updated content when the create action is run" do
        @node[:slappiness] = "a warm gun"
        @provider.should_receive(:backup)
        @provider.run_action(:create)
        IO.read(@rendered_file_location).should == "slappiness is a warm gun"
        @resource.should be_updated_by_last_action
      end

      it "should set the file access control as specified in the resource" do
        @resource.owner("adam")
        @resource.group("wheel")
        @resource.mode(00644)
        @provider.should_receive(:backup)
        @provider.should_receive(:set_all_access_controls)
        @provider.run_action(:create)
        @resource.should be_updated_by_last_action
      end

      it "doesn't overwrite the file when the create if missing action is run" do
        @node[:slappiness] = "a warm gun"
        @provider.should_not_receive(:backup)
        @provider.run_action(:create_if_missing)
        IO.read(@rendered_file_location).should == "blargh"
        @resource.should_not be_updated_by_last_action
      end
    end

    describe "when the target has the correct content" do
      before do
        Chef::ChecksumCache.instance.reset!
        File.open(@rendered_file_location, "w") { |f| f.print "slappiness is a warm gun" }
        @current_resource.checksum('4ff94a87794ed9aefe88e734df5a66fc8727a179e9496cbd88e3b5ec762a5ee9')
      end

      it "does not backup the original or overwrite it" do
        @node[:slappiness] = "a warm gun"
        @provider.should_not_receive(:backup)
        FileUtils.should_not_receive(:mv)
        @provider.run_action(:create)
        @resource.should_not be_updated_by_last_action
      end

      it "does not backup the original or overwrite it on create if missing" do
        @node[:slappiness] = "a warm gun"
        @provider.should_not_receive(:backup)
        FileUtils.should_not_receive(:mv)
        @provider.run_action(:create)
        @resource.should_not be_updated_by_last_action
      end

      it "sets the file access controls if they have diverged" do
        @provider.stub!(:backup).and_return(true)
        @resource.owner("adam")
        @resource.group("wheel")
        @resource.mode(00644)
        @provider.should_receive(:set_all_access_controls)
        @provider.should_receive(:backup)
        @provider.run_action(:create)
        @resource.should be_updated_by_last_action
      end
    end

  end
end
