# frozen_string_literal: true

require 'chef/knife'
require 'mixlib/shellout'

class Chef
  class Knife
    class Changelog < Knife
      banner 'knife changelog COOKBOOK [COOKBOOK ...]'

      deps do
        require 'knife/changelog/policyfile'
      end

      option :prevent_downgrade,
             long: '--prevent-downgrade',
             description: 'Fail if knife-changelog detect a cookbook downgrade',
             boolean: true,
             default: false

      option :policyfile,
             long: '--policyfile PATH',
             description: 'Link to policyfile, defaults to "Policyfile.rb"',
             default: 'Policyfile.rb'

      option :with_dependencies,
             long: '--with-dependencies',
             description: 'Show changelog for cookbook in Policyfile with dependencies',
             boolean: true,
             default: false

      def run
        Log.info config.to_s
        puts PolicyChangelog.new(
          @name_args,
          config[:policyfile],
          config[:with_dependencies]
        ).generate_changelog(config[:prevent_downgrade])
      end
    end
  end
end
