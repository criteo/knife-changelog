# frozen_string_literal: true

require 'chef/knife'
require 'mixlib/shellout'

class Chef
  class Knife
    class Changelog < Knife
      banner 'knife changelog COOKBOOK [COOKBOOK ...]'

      deps do
        require 'knife/changelog/version'
        require 'knife/changelog/changelog'
        require 'knife/changelog/policyfile'
        require 'knife/changelog/berksfile'
        require 'berkshelf'
      end

      option :linkify,
             short: '-l',
             long: '--linkify',
             description: 'add markdown links where relevant',
             boolean: true

      option :markdown,
             short: '-m',
             long: '--markdown',
             description: 'use markdown syntax',
             boolean: true

      option :ignore_changelog_file,
             long: '--ignore-changelog-file',
             description: 'Ignore changelog file presence, use git history instead',
             boolean: true

      option :allow_update_all,
             long: '--allow-update-all',
             description: 'If no cookbook given, check all Berksfile',
             boolean: true,
             default: true

      option :submodules,
             long: '--submodules SUBMODULE[,SUBMODULE]',
             description: 'Submoduless to check for changes as well (comma separated)'

      option :policyfile,
             long: '--policyfile PATH',
             description: 'Link to policyfile, defaults to "Policyfile.rb"',
             default: 'Policyfile.rb'

      option :update,
             long: '--update',
             description: 'Update Berksfile'

      def run
        Log.info config
        if config[:policyfile] && File.exist?(config[:policyfile])
          PolicyChangelog.new(@name_args, config[:policyfile]).generate_changelog
        else
          berksfile = Berkshelf::Berksfile.from_options({})
          @changelog = KnifeChangelog::Changelog::Berksfile.new(berksfile, config)
          changelog_text = @changelog.run(@name_args)
          puts changelog_text
        end
      end
    end
  end
end
