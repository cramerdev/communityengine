require 'ostruct'
require 'yaml'
begin
  require 'desert'
rescue LoadError => le
  $stderr.puts "Please install the desert gem: gem install desert --source http://gemcutter.org"
  raise le
end

module CommunityEngine
  def root
    @root ||= Pathname.new(File.expand_path(File.dirname(__FILE__) + '/..'))
  end
  module_function :root
  
  # Checks each of the +configs+ in turn for a configuration setting.
  # This will usually be something like:
  # 1) Check the hosting application's AppConfig
  # 2) Check CommunityEngine's AppConfig
  class AppConfigProxy
    attr_accessor :configs
    def initialize(configs)
      @configs = configs
    end
    
    def method_missing(m, *a)
      @configs.each do |config|
        return config.send(m, *a) if config.respond_to?(m)
      end
      
      nil
    end
  end
  
  class Environment
    class << self
      # Configure the hosting Rails application with Community Engine.
      # Add the CE plugin, the CE-specific plugins it comes with, and adds the
      # gems CE relies on.
      #
      # In your environment.rb, place this line:
      #
      # require Rails.root.join(*%w(vendor plugins community_engine config environment.rb))
      #
      # before your "Rails::Initializer.run do |config|" block.
      # Then place this line:
      # 
      # CommunityEngine::Environment.configure!(config)
      #
      # inside it, preferably toward the bottom so CE can detect what gems
      # you're running already.
      def configure!(config, options = {})
        # Add the CE plugin + white_list
        config.plugins ||= []
        config.plugins += [:community_engine, :white_list, :all]
        config.plugins.uniq!
        
        # Add in the CE specific plugins.
        plugins_root = CommunityEngine.root.join('plugins')
        plugin_glob = plugins_root.join('*')
        
        config.plugin_paths += if options[:plugins_exclude]
          Dir[plugins_glob].reject{|p| p =~ options[:plugins_exclude]}
        elsif options[:plugins_include]
          Dir[plugins_glob].select{|p| p =~ options[:plugins_include]}
        else
          [plugins_root]
        end
        
        # CE gems
        [
          ['hpricot'],
          ['calendar_date_select'],
          ['icalendar'],
          # You may need to install ImageMagick. Yuck.
          # OSX: sudo port install ImageMagick
          ['rmagick'],
          ['htmlentities'],
          ['rake', {:version => '~> 0.8.3'}],
          ['ri_cal'],
          ['aws-s3', {:lib => "aws/s3"}]
        ].each do |name, options|
          #unless find_gem(config.gems, name, options)
            config.gem name, (options || {}).merge(:source => 'http://gemcutter.org')
          #end
        end
        
        # Boot CE after initialize
        config.after_initialize do
          require CommunityEngine.root.join('config', 'boot.rb')
        end
      end # def configure
      
      # This is run from CE_ROOT/init.rb
      # Possible CE::AppConfig yaml locations can be:
      # - config/application.yml
      # - config/community_engine/application.yml
      # - (default) vendor/plugins/community_engine/config/application.yml
      #
      # The application configuration can be accessed from
      # CommunityEngine::AppConfig, namespaced so it doesn't hurt the main 
      # app's config. If you don't have your own AppConfig, you can embed it in
      # your app by placing:
      # ::AppConfig = CommunityEngine::AppConfig
      # at the bottom of your environment.rb.
      def load_app_config!
        locations = [
          Rails.root.join('config', 'application.yml'),
          Rails.root.join('config', 'community_engine', 'application.yml'),
          CommunityEngine.root.join('config', 'application.yml')
        ].map{|l| File.join(*l)}.select{|l| File.exists?(l)}
        
        config_hash = locations.inject({}) do |hash, location|
          contents = File.read(location)
          erb_interp = ERB.new(contents).result
          yaml_hash = YAML.load(erb_interp) || {}
          hash.reverse_merge!(yaml_hash)
          hash
        end
        
        ce_config = OpenStruct.new(config_hash)
        configs = [ce_config]
        configs.unshift(::AppConfig) if Object.const_defined?('AppConfig')

        Object.const_set("AppConfig", AppConfigProxy.new(configs))
        CommunityEngine.const_set("AppConfig", ce_config)
      end

      # # TODO: Make this work.
      # def find_gem(gems, name, options)
      #   gem = gems.find{|g| g.name == name}
      #   if options[:version]
      #     ce_req = Gem::Requirement.create(options[:version])
      #     gem.requirement.satisfy?(ce_req.requirements[0][0])
      #   else
      #     gem
      #   end
      # end
    end # class << self
  end # Configurator
end # CommunityEngine