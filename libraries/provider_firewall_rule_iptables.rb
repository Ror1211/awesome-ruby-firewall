#
# Cookbook Name:: firewall
# Provider:: rule_iptables
#
# Copyright 2012, computerlyrik
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
  class Provider::FirewallRuleIptables < Provider
    include Poise
    include Chef::Mixin::ShellOut
    include FirewallCookbook::Helpers
    provides :firewall_rule, :os => 'linux', :platform_family => ['rhel']

    def action_allow
      converge_by("Allowing #{new_resource.name}") do
        apply_rule(:allow)
      end
    end

    def action_deny
      converge_by("Denying #{new_resource.name}") do
        apply_rule(:deny)
      end
    end

    def action_reject
      converge_by("Rejecting #{new_resource.name}") do
        apply_rule(:reject)
      end
    end

    def action_redirect
      converge_by("redirect #{new_resource.name}") do
        apply_rule(:redirect)
      end
    end

    def action_masquerade
      converge_by("masquerade #{new_resource.name}") do
        apply_rule(:masquerade)
      end
    end

    def action_log
      converge_by("log #{new_resource.name}") do
        apply_rule(:log)
      end
    end

    private

    CHAIN = { :in => 'INPUT', :out => 'OUTPUT', :pre => 'PREROUTING', :post => 'POSTROUTING' } # , nil => "FORWARD"}
    TARGET = { :allow => 'ACCEPT', :reject => 'REJECT', :deny => 'DROP', :masquerade => 'MASQUERADE', :redirect => 'REDIRECT', :log => 'LOG --log-prefix "iptables: " --log-level 7' }

    def apply_rule(type = nil)
      firewall_command = 'iptables '
      if new_resource.position
        firewall_command << '-I ' # {new_resource.position} "
      else
        firewall_command << '-A '
      end

      # TODO: implement logging for :connections :packets
      log_current_iptables
      firewall_rule_local = firewall_rule(type)

      Chef::Log.debug("#{new_resource}: #{firewall_rule_local}")
      if rule_exists?(firewall_rule_local)
        Chef::Log.warn("#{new_resource} #{type} rule exists... won't apply")
      else
        cmdstr = firewall_command + firewall_rule_local
        converge_by("#{new_resource}: Adding rule - #{firewall_rule_local}") do
          shell_out!(cmdstr) # shell_out! is already logged
          new_resource.updated_by_last_action(true)
        end
      end

      log_current_iptables
    end

    def firewall_rule(type = nil)
      if new_resource.raw
        firewall_rule = new_resource.raw.strip!
      else
        firewall_rule = ''
        if new_resource.direction
          firewall_rule << "#{CHAIN[new_resource.direction.to_sym]} "
        else
          firewall_rule << 'FORWARD '
        end
        firewall_rule << "#{new_resource.position} " if new_resource.position

        if [:pre, :post].include?(new_resource.direction)
          firewall_rule << '-t nat '
        end
        firewall_rule << "-s #{new_resource.source} " if new_resource.source
        firewall_rule << "-p #{new_resource.protocol} " if new_resource.protocol
        firewall_rule << '-m tcp ' if new_resource.protocol.to_sym == :tcp
        firewall_rule << "-m multiport --sports #{port_to_s(new_resource.source_port)} " if new_resource.source_port
        firewall_rule << "-m multiport --dports #{dport_calc} " if dport_calc
        firewall_rule << "-i #{new_resource.interface} " if new_resource.interface
        firewall_rule << "-o #{new_resource.dest_interface} " if new_resource.dest_interface
        firewall_rule << "-d #{new_resource.destination} " if new_resource.destination
        firewall_rule << "-m state --state #{new_resource.stateful.is_a?(Array) ? new_resource.stateful.join(',').upcase : new_resource.stateful.upcase} " if new_resource.stateful
        firewall_rule << "-m comment --comment \"#{new_resource.description}\" "
        firewall_rule << "-j #{TARGET[type]} "
        firewall_rule << "--to-ports #{new_resource.redirect_port} " if type == 'redirect'
        firewall_rule.strip!
      end
      firewall_rule
    end

    def log_current_iptables
      cmdstr = 'iptables -L'
      Chef::Log.info("#{new_resource} log_current_iptables (#{cmdstr}):")
      cmd = shell_out!(cmdstr)
      Chef::Log.info(cmd.inspect)
    rescue
      Chef::Log.info("#{new_resource} log_current_iptables failed!")
    end

    def rule_exists?(rule)
      fail 'no rule supplied' unless rule
      if new_resource.position
        detect_rule = rule.gsub(/#{CHAIN[new_resource.direction]}\s(\d+)/, '\1' + " -A #{CHAIN[new_resource.direction]}")
      else
        detect_rule = rule
      end

      line_number = 0
      match = shell_out!("iptables -S #{CHAIN[new_resource.direction]}").stdout.lines.find do |line|
        next if line[1] == 'P'
        line_number += 1
        line = "#{line_number} #{line}" if new_resource.position
        Chef::Log.debug("matching: [#{detect_rule}] to [#{line.chomp.rstrip}]")
        line.chomp.rstrip =~ /#{detect_rule}/
      end

      Chef::Log.debug("Found a matching line: #{match}")
      true if match
      false
    rescue Mixlib::ShellOut::ShellCommandFailed
      Chef::Log.debug("#{new_resource} check fails with: " + cmd.inspect)
      Chef::Log.debug("#{new_resource} assuming #{rule} rule does not exist")
      false
    end

    def dport_calc
      new_resource.dest_port || new_resource.port
    end
  end
end
