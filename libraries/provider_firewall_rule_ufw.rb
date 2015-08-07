#
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Cookbook Name:: firwall
# Resource:: rule
#
# Copyright:: 2011, Opscode, Inc.
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
  class Provider::FirewallRuleUfw < Chef::Provider::LWRPBase
    include FirewallCookbook::Helpers::Ufw

    action :create do
      firewall = run_context.resource_collection.find(firewall: new_resource.firewall_name)
      firewall.rules Hash.new unless firewall.rules
      firewall.rules['ufw'] = Hash.new unless firewall.rules['ufw']

      if firewall.disabled
        Chef::Log.warn("#{firewall} has attribute 'disabled' = true, not proceeding")
        next
      end

      # build rules to apply with weight
      k = build_rule(new_resource)
      v = new_resource.position

      # unless we're adding them for the first time.... bail out.
      unless firewall.rules['ufw'].key?(k) && firewall.rules['ufw'][k] == v
        firewall.rules['ufw'][k] = v

        new_resource.notifies(:restart, firewall, :delayed)
        new_resource.updated_by_last_action(true)
      end

    end

  end
end
