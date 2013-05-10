require 'rubygems'
require 'bundler/setup'
require 'parallel'

module OpenShift
  module Deployment
    def self.read_gear_registry
      gears = []
      File.open(File.join(ENV['OPENSHIFT_HOMEDIR'], 'haproxy-1.4', 'conf', 'gear-registry.db')).each do |line|
        # eade013180c842af98947e5728e88c1e@10.7.14.215:ruby-1.9;eade013180-andy.ose.rhc.redhat.com
        if line =~ /([^@]+)@([^:]+):/
          uuid, host = $~[1..2]
          gears << [uuid, host]
        end
      end
      gears
    end
    
    def self.each_gear(gears=nil, &block)
      gears ||= read_gear_registry
      puts "# of child gears = #{gears.count}"
      Parallel.each(gears, :in_threads => 5, &block)
    end
  end
end
