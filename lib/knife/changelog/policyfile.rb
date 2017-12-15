# frozen_string_literal: true

require_relative 'changelog'

class KnifeChangelog
  class Changelog
    class Policyfile < Changelog
      attr_reader :policy, :lock

      def initialize(policyfile_path, config)
        require 'chef-dk'
        require 'chef-dk/policyfile_compiler'
        lock_path = policyfile_path.gsub(/.rb$/, '.lock.json')
        @policy = ChefDK::PolicyfileCompiler.evaluate(File.read(policyfile_path), policyfile_path)
        @lock = ChefDK::PolicyfileLock.new(policy.storage_config).build_from_lock_data(JSON.parse(File.read(lock_path)))
        super(config)
      end

      def all_cookbooks
        policy.solution_dependencies.cookbook_deps_for_lock.map { |k, v| k.scan(/(.*) \(.*\)/).last.first }
      end

      # return true if cookbook is not already listed as dependency
      def new_cookbook?(name)
        policy.send(:best_source_for, name).nil?
      end

      # return true if cookbook is downloaded from supermarket
      def supermarket?(name)
        # it's hard to get location_specs for supermarket cookbooks without having policy_compiler starting to download all cookbooks
        # in the meantime, we procede by elimination
        !(git?(name) || local?(name))
      end

      def guess_version_for(name)
        lock.solution_dependencies.cookbook_dependencies.keys.find { |dep| dep.name == name }.version
      end

      # return true if cookbook is downloaded from git
      def git?(name)
        # cookbook_location_specs contains only cookbooks refered via git and path
        policy.cookbook_location_specs[name] && policy.cookbook_location_specs[name].source_type == :git
      end

      # return true if cookbook is downloaded from local path
      def local?(name)
        # cookbook_location_specs contains only cookbooks refered via git and path
        policy.cookbook_location_specs[name] && policy.cookbook_location_specs[name].source_type.nil?
      end

      # return a Changelog::Location for a given cookbook
      def git_location(name)
        return nil unless git?(name)
        spec = lock.cookbook_locks[name].source_options
        Location.new(spec[:git], spec[:revision], spec[:branch])
      end

      def update(cookbooks)
        raise NotImplementedError
      end

      # return a list of supermarket uri for a given cookbook
      # example: [ 'https://supermarket.chef.io' ]
      def supermarkets_for(name)
        [policy.send(:best_source_for, name).uri]
      end
    end
  end
end
