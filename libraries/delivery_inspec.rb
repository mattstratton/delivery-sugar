#
# Copyright:: Copyright (c) 2015 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/mixin/shell_out'
require_relative './delivery_dsl'
require 'chef/dsl'

module DeliverySugar
  #
  # This class is our interface to execute inspec tests
  #
  class Inspec
    include Chef::DSL::Recipe
    include DeliverySugar::DSL
    include Chef::Mixin::ShellOut
    attr_reader :repo_path, :os, :node
    attr_accessor :run_context

    #
    # Create a new Inspec object
    #
    # @param repo_path [String]
    #   The path to the project repository within the workspace
    # @param run_context [Chef::RunContext]
    #   The object that loads and tracks the context of the Chef run
    # @param yaml [String]
    #   The name of the Kitchen YAML file
    #
    # @return [DeliverySugar::Inspec]
    #
    def initialize(repo_path, run_context, parameters = {})
      @repo_path = repo_path
      @run_context = run_context
      @os = parameters[:os]
      @infra_node = parameters[:infra_node]
    end

    #
    # Run inspec action
    #
    def run_inspec
      prepare_linux_inspec
      shell_out!(
        "#{cache}/inspec.sh",
        cwd: @repo_path,
        live_stream: STDOUT
      )
    end

    #
    # Create script for linux nodes
    #
    # rubocop:disable AbcSize
    # rubocop:disable Metrics/MethodLength
    def prepare_linux_inspec
      # Load secrets from delivery-secrets data bag
      secrets = get_project_secrets
      fail 'Could not find secrets for inspec' \
           ' in delivery-secrets data bag.' if secrets['inspec'].nil?
      # Variables used for the linux inspec script
      ssh_user = secrets['inspec']['ssh-user']
      ssh_private_key_file = "#{cache}/.ssh/#{secrets['inspec']['ssh-user']}.pem"

      # Create directory for SSH key
      directory = Chef::Resource::Directory.new("#{cache}/.ssh", run_context)
      directory.recursive true
      directory.run_action(:create)

      # Create private key
      file = Chef::Resource::File.new(ssh_private_key_file, run_context).tap do |f|
        f.content secrets['ec2']['private_key']
        f.sensitive true
        f.mode '0400'
      end
      file.run_action(:create)

      # Create inspec script
      file = Chef::Resource::File.new("#{cache}/inspec.sh").tap do |f|
        f.content '/opt/chefdk/embedded/bin/inspec ' \
                  "exec #{node['delivery']['workspace']['repo']}/" \
                  'test/recipes/ ' \
                  "-t ssh://#{ssh_user}@#{infra_node} " \
                  "-i #{ssh_key_path}"
        f.sensitive true
        f.mode '0750'
      end
      file.run_action(:create)
    end
  end
end
