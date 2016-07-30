require 'puma'
require 'rake/sprocketstask'
require 'sinatra/asset_pipeline/task'
require_relative 'app'
require_relative 'misc/configuration'

def fetch(*args) Configuration.instance.fetch(*args) end
def execute(*args) Kernel.exec args.join(' ') end

Configuration.instance do
  set :puma_cmd, -> { [fetch(:bundle_cmd, :bundle), 'exec puma'] }
end

namespace :puma do
  desc 'Start puma'
  task :start do
    execute *fetch(:puma_cmd), "-e #{puma_env} -C #{config_file}"
  end

  def config_file
    @_config_file ||= begin
      file = fetch(:puma_config_file, nil)
      file = "./config/puma.rb" if file.nil? && File.exists?('./config/puma.rb')
      file = "./config/puma/#{puma_env}.rb" if file.nil? && File.exists?("./config/puma/#{puma_env}.rb")
      file
    end
  end

  def puma_env
    pe = configuration.options[:environment]
    pe || fetch(:rack_env, fetch(:rack_env, 'production'))
  end

  def configuration
    require 'puma/configuration'
    Puma::Configuration.new(config_file: config_file).tap(&:load)
  end
end

Sinatra::AssetPipeline::Task.define! Application

task default: ['puma:start']
