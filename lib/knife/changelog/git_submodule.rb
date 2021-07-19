# coding: utf-8
require 'chef/log'
require_relative 'changelog'

class KnifeChangelog
  class GitSubmodule < Changelog

    def run(submodules)
      raise ::ArgumentError, "Submodules must be an Array instead of #{submodules.inspect}" unless submodules.is_a?(::Array)
      submodules.map do |submodule|
        Chef::Log.debug "Checking changelog for #{submodule} (submodule)"
        format_changelog(submodule, *handle_submodule(submodule))
      end.compact.join("\n")
    ensure
      clean
    end
  end
end
