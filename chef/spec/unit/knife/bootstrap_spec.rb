#
# Author:: Ian Meyer (<ianmmeyer@gmail.com>)
# Copyright:: Copyright (c) 2010 Ian Meyer
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

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))

require 'net/ssh'

describe Chef::Knife::Bootstrap do
  before(:each) do
    Chef::Log.logger = Logger.new(StringIO.new)

    @knife = Chef::Knife::Bootstrap.new
    @knife.config[:template_file] = File.expand_path(File.join(CHEF_SPEC_DATA, "bootstrap", "test.erb"))
  end

  it "should load the default bootstrap template" do
    @knife.load_template.should be_a_kind_of(String)
  end

  it "should error if template can not be found" do
    @knife.config[:template_file] = false
    @knife.config[:distro] = 'penultimate'
    lambda { @knife.load_template }.should raise_error
  end

  it "should load the specified template" do
    @knife.config[:distro] = 'fedora13-gems'
    lambda { @knife.load_template }.should_not raise_error
  end

  it "should return an empty run_list" do
    template_string = @knife.load_template(@knife.config[:template_file])
    @knife.render_template(template_string).should == '{"run_list":[]}'
  end

  it "should have role[base] in the run_list" do
    template_string = @knife.load_template(@knife.config[:template_file])
    @knife.parse_options(["-r","role[base]"])
    @knife.render_template(template_string).should == '{"run_list":["role[base]"]}'
  end

  it "should have role[base] and recipe[cupcakes] in the run_list" do
    template_string = @knife.load_template(@knife.config[:template_file])
    @knife.parse_options(["-r", "role[base],recipe[cupcakes]"])
    @knife.render_template(template_string).should == '{"run_list":["role[base]","recipe[cupcakes]"]}'
  end

  it "should take the node name from ARGV" do
    @knife.name_args = ['barf']
    @knife.name_args.first.should == "barf"
  end

  describe "when configuring the underlying knife ssh command" do
    before do
      @knife.name_args = ["foo.example.com"]
      @knife.config[:ssh_user]      = "rooty"
      @knife.config[:ssh_password]  = "open_sesame"
      Chef::Config[:knife][:ssh_port] = "4001"
      @knife.config[:identity_file] = "~/.ssh/me.rsa"
      @knife_ssh = @knife.knife_ssh
    end

    it "configures the hostname" do
      @knife_ssh.name_args.first.should == "foo.example.com"
    end

    it "configures the ssh user" do
      @knife_ssh.config[:ssh_user].should == 'rooty'
    end

    it "configures the ssh password" do
      @knife_ssh.config[:ssh_password].should == 'open_sesame'
    end

    it "configures the ssh port" do
      @knife_ssh.config[:ssh_port].should == '4001'
    end

    it "configures the ssh identity file" do
      @knife_ssh.config[:identity_file].should == '~/.ssh/me.rsa'
    end
  end

  describe "when falling back to password auth when host key auth fails" do
    before do
      @knife.name_args = ["foo.example.com"]
      @knife.config[:ssh_user]      = "rooty"
      @knife.config[:identity_file] = "~/.ssh/me.rsa"
      @knife_ssh = @knife.knife_ssh
    end

    it "prompts the user for a password " do
      @knife.stub!(:knife_ssh).and_return(@knife_ssh)
      @knife_ssh.stub!(:get_password).and_return('typed_in_password')
      alternate_knife_ssh = @knife.knife_ssh_with_password_auth
      alternate_knife_ssh.config[:ssh_password].should == 'typed_in_password'
    end

    it "configures knife not to use the identity file that didn't work previously" do
      @knife.stub!(:knife_ssh).and_return(@knife_ssh)
      @knife_ssh.stub!(:get_password).and_return('typed_in_password')
      alternate_knife_ssh = @knife.knife_ssh_with_password_auth
      alternate_knife_ssh.config[:identity_file].should be_nil
    end
  end

  describe "when running the bootstrap" do
    before do
      @knife.name_args = ["foo.example.com"]
      @knife.config[:ssh_user]      = "rooty"
      @knife.config[:identity_file] = "~/.ssh/me.rsa"
      @knife_ssh = @knife.knife_ssh
      @knife.stub!(:knife_ssh).and_return(@knife_ssh)
    end

    it "verifies that a server to bootstrap was given as a command line arg" do
      @knife.name_args = nil
      lambda { @knife.run }.should raise_error(SystemExit)
    end

    it "configures the underlying ssh command and then runs it" do
      @knife_ssh.should_receive(:run)
      @knife.run
    end

    it "falls back to password based auth when auth fails the first time" do
      @knife.stub!(:puts)

      @fallback_knife_ssh = @knife_ssh.dup
      @knife_ssh.should_receive(:run).and_raise(Net::SSH::AuthenticationFailed.new("no ssh for you"))
      @knife.stub!(:knife_ssh_with_password_auth).and_return(@fallback_knife_ssh)
      @fallback_knife_ssh.should_receive(:run)
      @knife.run
    end

  end

  describe "render_template" do
    
  end

end

describe Chef::Knife::Bootstrap::TemplateHelper do
  before(:each) do
    @context = Erubis::Context.new({
      :config => Hash.new
    })
  end

  describe "bootstrap_version_string" do
    after(:each) do
      Chef::Config.delete :bootstrap_version
    end

    formats = {
      :gems => /^--version \d+\.\d+\.\d+/,
      :nil =>  '\d+\.\d+\.\d+'
    }

    context "by default" do
      formats.each do |sym, format|
        it "should return the current version of Chef for :#{sym.to_s}" do
          @context.bootstrap_version_string(sym).should include Chef::VERSION
        end

        it "should match the correct output format for :#{sym.to_s}" do
          @context.bootstrap_version_string(sym).should match format
        end
      end
    end

    context "with Chef::Config[:bootstrap_version] set" do
      before(:each) do
        @config_version = "0.9.12"
        Chef::Config[:bootstrap_version] = @config_version
      end

      formats.each do |sym, format|
        it "should return the specified bootstrap version for :#{sym.to_s}" do
          @context.bootstrap_version_string(sym).should include @config_version
        end

        it "should match the correct output format for :#{sym.to_s}" do
          @context.bootstrap_version_string(sym).should match format
        end
      end
    end

    context "with config[:prerelease] set" do
      before(:each) do
        @context[:config][:prerelease] = true
      end

      it "should return --prerelease only for :gems" do
        formats.each do |sym, format|
          version_string = @context.bootstrap_version_string(sym)
          version_string.should == "--prerelease" if sym == :gems
          version_string.should_not == "--prerelease" if sym != :gems
        end
      end
    end
  end
end
