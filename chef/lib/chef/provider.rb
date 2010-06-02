#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Christopher Walters (<cw@opscode.com>)
# Copyright:: Copyright (c) 2008, 2009 Opscode, Inc.
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

require 'chef/mixin/from_file'
require 'chef/mixin/convert_to_class_name'
require 'chef/mixin/recipe_definition_dsl_core'

class Chef
  class Provider
    
    include Chef::Mixin::RecipeDefinitionDSLCore
    
    attr_accessor :new_resource, :current_resource, :run_context
    
    def initialize(new_resource, run_context)
      @new_resource = new_resource
      @current_resource = nil
      @run_context = run_context
    end

    def node
      run_context.node
    end
    
    def load_current_resource
      raise Chef::Exceptions::Override, "You must override load_current_resource in #{self.to_s}"
    end
    
    def action_nothing
      Chef::Log.debug("Doing nothing for #{@new_resource.to_s}")
      true
    end
    
    protected
    
    def recipe_eval(&block)
      # This block has new resource definitions within it, which
      # essentially makes it an in-line Chef run. Save our current
      # run_context and create one anew, so the new Chef run only
      # executes the embedded resources.
      #
      # TODO: timh,cw: 2010-5-14: This means that the resources within
      # this block cannot interact with resources outside, e.g.,
      # manipulating notifies.
      saved_run_context = run_context
      self.run_context = Chef::RunContext.new(saved_run_context.node, saved_run_context.cookbook_collection)
      
      instance_eval(&block)
      Chef::Runner.new(run_context).converge
      
      self.run_context = saved_run_context
    end
    
    public
    
    class << self
      include Chef::Mixin::ConvertToClassName
      
      def build_from_file(cookbook_name, filename)
        pname = filename_to_qualified_string(cookbook_name, filename)
        
        new_provider_class = Class.new self do |cls|
          
          def load_current_resource
            # silence Chef::Exceptions::Override exception
          end
          
          class << cls
            include Chef::Mixin::FromFile
            
            # setup DSL's shortcut methods
            def action(name, &block)
              define_method("action_#{name.to_s}") do
                instance_eval(&block)
              end
            end
          end
          
          # load provider definition from file
          cls.class_from_file(filename)
        end
        
        # register new class as a Chef::Provider
        pname = filename_to_qualified_string(cookbook_name, filename)
        class_name = convert_to_class_name(pname)
        Chef::Provider.const_set(class_name, new_provider_class)
        Chef::Log.debug("Loaded contents of #{filename} into a provider named #{pname} defined in Chef::Provider::#{class_name}")
        
        new_provider_class
      end
    end

  end
end
