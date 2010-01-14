#
# Author:: Christopher Walters (<cw@opscode.com>)
# Copyright:: Copyright (c) 2009 Opscode, Inc.
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

require 'chef/mixin/stack_trace'

class Chef
  module Mixin
    module Retry
      
      include Chef::Mixin::StackTrace
      
      def retry_with_delay(delay_generator, &block)
        iter = 0
        begin
          yield
        rescue Exception => e
          if delay_generator.next?
            delay = delay_generator.next
            Chef::Log.error(stack_trace(e))
            Chef::Log.error("Retry ##{iter += 1}, delaying #{delay}s")
            sleep delay
            retry
          else
            Chef::Log.error("Failed again and reached retry limit, so propagating the exception") unless iter == 0 # don't print unless retries were not requested
            throw e
          end
        end
      end
      
      # BUGBUG This is a poor man's duck shadow class (just made that up) of the
      # BUGBUG standard Generator class, because requiring the json gem
      # BUGBUG (at least against versions 1.1.4 and 1.2.0) causes require 'generator'
      # BUGBUG to not load the standard library's generator.rb. See CHEF-876.
      class Generator
        def initialize(queue)
          @queue = queue
        end
        
        def next
          raise EOFError, "no more elements available" unless next?
          queue.shift
        end
        
        def next?
          queue.any?
        end
      end
      
      class ExponentialBackoffDelayGenerator
        class << self
          def create(max_retries=3, scale=1)
            # TODO: once CHEF-876 is resolved, this will be the standard Generator
            Chef::Mixin::Retry::Generator.new([*0..(max_retries-1)].map{|exp| rand(scale*(1 << exp))})
          end
        end
      end
      
      class UniformBackoffDelayGenerator
        class << self
          def create(max_retries=3, delay=1)
            # TODO: once CHEF-876 is resolved, this will be the standard Generator
            Chef::Mixin::Retry::Generator.new([*0..(max_retries-1)].map{|elt| delay})
          end
        end
      end
      
    end
  end
end
