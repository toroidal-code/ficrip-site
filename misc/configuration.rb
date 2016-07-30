require 'singleton'

class Configuration < Delegator
  include Singleton

  class << self
    private
    alias_method :_instance, :instance
  end

  def self.instance(&block)
    _instance.instance_eval(&block) if block_given?
    _instance
  end

  def initialize(&block)
    @map = Hash.new
    instance_eval(&block) if block_given?
    self
  end

  def __getobj__
    @map
  end

  def fetch(key, default = nil)
    res = @map[key]
    res = res.call if res.is_a? Proc
    res ||= ENV[key.to_s.upcase]
    res || default
  end

  def set(*args)
    options = args.last.is_a?(Hash) ? args.pop : nil
    if options.nil? || options.empty?
      @map.send(:[]=, *args)
    else
      options.each_pair { |k, v| @map[k] = v }
    end
  end
end
