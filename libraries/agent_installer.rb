module AWSCloudwatch
  class AgentInstaller < Chef::Resource
    require_relative "agent_installer_helpers.rb"
    include AWSCloudwatch::AgentInstallerHelpers

    resource_name :aws_cloudwatch_agent

    property :config, String
    property :config_params, Hash, default: {'param' => 'value'}

    default_action :install

    provides :aws_cloudwatch_agent


    action :install do
      # Download installer
      package_files = {}
      ['package', 'sig'].each do |file|
        package_files[file] = ::File::join(Chef::Config[:file_cache_path], file_from_uri(node['aws_cloudwatch']['installers'][node[:platform]][file]))
        remote_file package_files[file] do
          action :create
          source node['aws_cloudwatch']['installers'][node[:platform]][file]
        end
      end

      package_files['gpg'] = ::File::join(Chef::Config[:file_cache_path], file_from_uri(node['aws_cloudwatch']['gpg']['public_key']))
      remote_file package_files['gpg'] do
        action :create
        notifies  :run, 'ruby_block[verify_installer]', :immediately
        source node['aws_cloudwatch']['gpg']['public_key']
      end

      # Verify installer
      ruby_block 'verify_installer' do
        action :nothing
        block do
          verify_args = {
            'platform' => node[:platform],
            'cwd' => Chef::Config[:file_cache_path],
            'fingerprint' => node['aws_cloudwatch']['gpg']['fingerprint']
          }
          verify_args.merge!(package_files)

          verify_installer(verify_args)
        end
      end

      # Install
      case node[:platform]
        when 'redhat', 'centos'
          yum_package 'amazon-cloudwatch-agent' do
            action  :install
            source  package_files['package']
          end
        when 'ubuntu', 'debian'
          dpkg_package 'amazon-cloudwatch-agent' do
            action  :install
            source  package_files['package']
          end
      end
    end

    action :configure do
      config = new_resource.config
      config_params = new_resource.config_params || {}

      node[:platform] == 'windows' ? \
        config_path = node['aws_cloudwatch']['config']['path']['windows'] : \
        config_path = node['aws_cloudwatch']['config']['path']['linux']

      config ? \
        config_source = config : \
        config_source = node['aws_cloudwatch']['config']['source']

      template ::File::join("#{config_path}", node['aws_cloudwatch']['config']['file_name']) do
        action    :create
        source    config_source

        # Use a resource config-file template if not provided in properties
        unless config
          cookbook  'aws_cloudwatch'
          variables(
            shared_credential_profile: config_params[:shared_credential_profile] || \
                                       node['aws_cloudwatch']['config']['params']['shared_credential_profile'] || \
                                       ENV['SHARED_CREDENTIAL_PROFILE'],
            shared_credential_file: config_params[:shared_credential_file] || \
                                    node['aws_cloudwatch']['config']['params']['shared_credential_file'] || \
                                    ENV['SHARED_CREDENTIAL_FILE'],
            http_proxy: config_params[:http_proxy] || \
                        node['aws_cloudwatch']['config']['params']['http_proxy'] || \
                        ENV['HTTP_PROXY'],
            https_proxy: config_params[:https_proxy] || \
                         node['aws_cloudwatch']['config']['params']['https_proxy'] || \
                         ENV['HTTPS_PROXY'],
            no_proxy: config_params[:no_proxy] || \
                      node['aws_cloudwatch']['config']['params']['no_proxy'] || \
                      ENV['NO_PROXY']
          )
        end
      end
    end

    action :delete do
      file '/tmp/agent' do
        action :delete
        content "yes"
      end
    end
  end
end