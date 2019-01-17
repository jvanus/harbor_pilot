module HarborPilot

  class << self
    attr_accessor :configuration
    def configuration
      @configuration ||= Configuration.new
    end
  end

  def self.configure
    yield(configuration)
  end

  class SecureCredentials < ActiveSupport::EncryptedConfiguration

    def initialize(config_path: HarborPilot::Engine.root.join("config/credentials.yml.enc"),
                   key_path: HarborPilot::Engine.root.join("config/master.key"), 
                   env_key: "RAILS_MASTER_KEY", 
                   raise_if_missing_key: true)
      super config_path: config_path, 
            key_path: key_path,
            env_key: env_key, 
            raise_if_missing_key: raise_if_missing_key
    end

    def config=(config)
      @config = config
    end

    def save!
      write config.to_yaml
    end
  end

  class Configuration
    DEFAULT_VERSION = "0.1.0"
    VERSION_FILENAME = ".version"
    attr_accessor :registry_path, :app_name, :service_name, 
                  :app_registry_path, :environments, :splunk_url,
                  :manager_node, :manager_user, :subdomain, 
                  :rails_env, :docker_user_config_path, :rails_master_key,
                  :registry_project_name, :route_path, :splunk_token, :version

    def initialize
      @route_path              = '/'
      @registry_path           = 'hub.docker.com'
      @app_name                = Rails.application.engine_name.remove("_application")
      @service_name            = app_name.remove("_")
      @registry_project_name   = app_name
      @rails_env               = Rails.env
      @docker_user_config_path = "#{ENV['HOME']}/.docker/config.json"
      @rails_master_key        = "#{ENV['RAILS_MASTER_KEY']}"
      @environments            = { 
        staging: 
          { manager_node: 'localhost',
            manager_user: 'root',
            subdomain:    'staging',
            rails_env:    'staging'
          }, 
        cybersec: 
          { manager_node: 'localhost',
            manager_user: 'root',
            subdomain:    'cybersecurity',
            rails_env:    'cybersec'
          },
        production: 
          { manager_node: 'localhost',
            manager_user: 'root',
            subdomain:    'uhapps',
            rails_env:    'production'
          }  
      }
    end

    def app_registry_path
      @app_registry_path || "#{registry_path}/#{registry_project_name}"
    end

    def version
      @version ||= read_version_from_file
    end

    def secrets_to_filter
      secure_creds.keys + [:rails_master_key]
    end

    ##
    # A list of config values that are needed by the shell
    def env_variables
      %w{rails_master_key splunk_url splunk_token 
        rails_env subdomain service_name version app_registry_path }
    end

    ##
    # The environment variables represented as a hash
    def env
      env_variables
      .reject { |var| send(var).nil?   }
      .map    { |var| [var, send(var)] }
      .to_h
    end

    ##
    # The environment varialbes made useable by the shell
    def shell_env
      env.transform_keys!(&:upcase)
    end

    ##
    # Returns a Configuration object for the given env.
    # 
    # Overwrights the values from the environments[env] hash with the 
    # values in self
    def for(env)
      return self unless environments[env.to_sym]
      environments[env.to_sym].inject(self) do |merged, tupple|
        key, value = tupple
        merged.send(key.to_s + "=", value)
        self
      end
    end


    private 
    def secure_creds
      @secure_creds ||= SecureCredentials.new.config
    end

    def read_version_from_file
      if File.exist?(VERSION_FILENAME)
        File.readlines(VERSION_FILENAME).first.strip
      else
        DEFAULT_VERSION
      end
    end

  end

end
