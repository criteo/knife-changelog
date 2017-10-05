# frozen_string_literal: true

require_relative 'changelog'

class KnifeChangelog
  class Changelog
    class Berksfile < Changelog
      def initialize(locked_versions, config, sources)
        require 'berkshelf'
        @locked_versions = locked_versions
        @sources = sources
        super(config)
      end

      def all_cookbooks
        @locked_versions.keys
      end

      def new_cookbook?(name)
        ck_dep(name).nil?
      end

      # return true if cookbook is downloaded from supermarket
      def supermarket?(name)
        # here is berkshelf "expressive" way to say cookbook
        # comes from supermarket
        ck_dep(name).location.is_a?(NilClass)
      end

      # return true if cookbook is downloaded from git
      def git?(name)
        ck_dep(name).location.is_a?(Berkshelf::GitLocation)
      end

      # return true if cookbook is downloaded from local path
      def local?(name)
        ck_dep(name).location.is_a?(Berkshelf::PathLocation)
      end

      # return a Changelog::Location for this cookbook
      def git_location(name)
        raise "#{name} has not a git location" unless git?(name)
        Location.from_berk_git_location(ck_dep(name).location)
      end

      # return a list of supermarket uri for a given cookbook
      # example: [ 'https://supermarket.chef.io' ]
      def supermarkets_for(_name)
        @sources.map(&:uri)
      end

      def guess_version_for(name)
        @locked_versions[name].locked_version.to_s
      end

      private

      def ck_dep(name)
        @locked_versions[name]
      end
    end
  end
end
