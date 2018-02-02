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
        require 'knife/changelog/berksfile'
        require 'berkshelf'
        require 'policyfile'
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

      option :with_dependencies,
             long: '--with-dependencies',
             description: 'Show changelog for cookbook in Policyfile with dependencies',
             boolean: true,
             default: false

      option :update,
             long: '--update',
             description: 'Update Berksfile'

      def run
        Log.info config
        if config[:policyfile] && File.exist?(config[:policyfile])
          puts PolicyChangelog.new(
            @name_args,
            config[:policyfile],
            config[:with_dependencies]
          ).generate_changelog
        else
          berksfile = Berkshelf::Berksfile.from_options({})
          puts KnifeChangelog::Changelog::Berksfile
            .new(berksfile, config)
            .run(@name_args)
        end
      end
    end
  end
end
