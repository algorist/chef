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

class Chef
  module Mixin
    module StackTrace
      
      def stack_trace(exception)
        head, *tail = exception.backtrace
        msg = "#{head}: #{exception.message} (#{exception.class})"
        msg << "\n\tfrom " + tail.join("\n\tfrom ") unless tail.empty?
      end

      # Debugging a call stack: adapted from http://sick.snusnu.info/2008/10/09/debugging-the-call-stack-using-puts-and-caller-in-ruby/
      def call_stack(from = 2, to = nil)
        [*from..(to||caller.length)].map{|idx| "[#{idx}]: #{caller[idx]}"}.join("\n")
      end

    end
  end
end
