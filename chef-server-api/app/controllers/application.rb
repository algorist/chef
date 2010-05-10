#
#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Christopher Brown (<cb@opscode.com>)
# Author:: Christopher Walters (<cw@opscode.com>)
# Author:: Tim Hinderliter (<tim@opscode.com>)
# Copyright:: Copyright (c) 2008, 2009, 2010 Opscode, Inc.
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

require "chef" / "mixin" / "checksum"
require "mixlib/authentication/signatureverification"

class ChefServerApi::Application < Merb::Controller

  include Chef::Mixin::Checksum

  controller_for_slice
  
  # Generate the absolute url for a slice - takes the slice's :path_prefix into account.
  #
  # @param slice_name<Symbol> 
  #   The name of the slice - in identifier_sym format (underscored).
  # @param *args<Array[Symbol,Hash]> 
  #   There are several possibilities regarding arguments:
  #   - when passing a Hash only, the :default route of the current 
  #     slice will be used
  #   - when a Symbol is passed, it's used as the route name
  #   - a Hash with additional params can optionally be passed
  # 
  # @return <String> A uri based on the requested slice.
  #
  # @example absolute_slice_url(:awesome, :format => 'html')
  # @example absolute_slice_url(:forum, :posts, :format => 'xml')          
  def absolute_slice_url(slice_name, *args)
    options = {}
    if args.length == 1 && args[0].respond_to?(:keys)
      options = args[0]
    else
      options  = extract_options_from_args!(args) || {}
    end
    protocol = options.delete(:protocol) || request.protocol
    host     = options.delete(:host) || request.host
    protocol + "://" + host + slice_url(slice_name, *args)
  end
  
  def authenticate_every
    authenticator = Mixlib::Authentication::SignatureVerification.new

    auth = begin
             headers = request.env.inject({ }) { |memo, kv| memo[$2.downcase.gsub(/\-/,"_").to_sym] = kv[1] if kv[0] =~ /^(HTTP_)(.*)/; memo }
             Chef::Log.debug("Headers in authenticate_every: #{headers.inspect}")
             username = headers[:x_ops_userid].chomp
             Chef::Log.info("Authenticating client #{username}")
             user = Chef::ApiClient.cdb_load(username)
             Chef::Log.debug("Found API Client: #{user.inspect}")
             user_key = OpenSSL::PKey::RSA.new(user.public_key)
             Chef::Log.debug "Authenticating:\n #{user.inspect}\n"
             # Store this for later..
             @auth_user = user
             authenticator.authenticate_user_request(request, user_key)
           rescue StandardError => se
             Chef::Log.debug "Authentication failed: #{se}, #{se.backtrace.join("\n")}"
             nil
           end

    raise Unauthorized, "Failed to authenticate!" unless auth

    auth
  end
  
  def is_admin 
    if @auth_user.admin
      true
    else
      raise Unauthorized, "You are not allowed to take this action."
    end
  end

  def is_correct_node
    if @auth_user.admin || @auth_user.name == params[:id]
      true
    else
      raise Unauthorized, "You are not the correct node (auth_user name: #{@auth_user.name}, params[:id]: #{params[:id]}), or are not an API administrator (admin: #{@auth_user.admin})."
    end
  end
  
  # Store the URI of the current request in the session.
  #
  # We can return to this location by calling #redirect_back_or_default.
  def store_location
    session[:return_to] = request.uri
  end

  # Redirect to the URI stored by the most recent store_location call or
  # to the passed default.
  def redirect_back_or_default(default)
    loc = session[:return_to] || default
    session[:return_to] = nil
    redirect loc
  end
  
  def access_denied
    case content_type
    when :html
      store_location
      redirect slice_url(:openid_consumer), :message => { :error => "You don't have access to that, please login."}
    else
      raise Unauthorized, "You must authenticate first!"
    end
  end

  def cookbooks_for_node(node_name)
    # get node's explicit dependencies
    node = Chef::Node.cdb_load(node_name)
    run_list_items, default_attrs, override_attrs = node.run_list.expand('couchdb')
    
    # walk run list and accumulate included dependencies
    all_cookbooks = Chef::Cookbook.cdb_list(true)
    run_list_item.inject({}) do |included_cookbooks, run_list_item|
      expand_cookbook_deps(included_cookbooks, all_cookbooks, run_list_item)
      included_cookbooks
    end
  end
  
  # Accumulates transitive cookbook dependencies no more than once in included_cookbooks
  def expand_cookbook_deps(included_cookbooks, all_cookbooks, run_list_item)
    # determine the run list item's parent cookbook, which might be run_list_item in the default case
    cookbook = (run_list_item =~ /^(.+)::/ ? $1 : run_list_item)
    Chef::Log.debug("Node requires #{cookbook}")

    # include its dependencies
    included_cookbooks[cookbook] = true
    all_cookbooks.metadata[cookbook.to_sym].dependencies.each do |dep, versions|
      expand_cookbook_deps(included_cookbooks, all_cookbooks, dep) unless included_cookbooks[dep]
    end
  end
  
  def load_all_files(node_name=nil)
    included_cookbooks = node_name ? cookbooks_for_node(node_name) : {} 
    nodes_cookbooks = Hash.new
    included_cookbooks.each do |cookbook|
      if node_name
        next unless included_cookbooks[cookbook.name.to_s]
      end
      nodes_cookbooks[cookbook.name.to_s] = cookbook.generate_manifest_with_urls{|opts| absolute_slice_url(:cookbook_file, opts) }
    end
    nodes_cookbooks
  end

  def get_available_recipes
    all_cookbooks = Chef::Cookbook.cdb_list(true)
    available_recipes = all_cookbooks.sort{ |a,b| a.name.to_s <=> b.name.to_s }.inject([]) do |result, element|
      element.recipes.sort.each do |r| 
        if r =~ /^(.+)::default$/
          result << $1
        else
          result << r
        end
      end
      result
    end
    available_recipes
  end

end

