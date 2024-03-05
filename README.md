# Knife::Changelog

knife-changelog aims to make find cookbook changelogs easily to help upgrades.

Using it will create changelogs from your current version to most up-to-date version.

Usage : `knife changelog COOKBOOK [COKKBOOK...]`

Options: 
- `--linkify` or `-l` outputs markdown with links to commits
- `--ignore-changelog-file` allow to force the usage of raw git history instead of Changelog file

## Features

- generate changelogs for some supermarket hosted cookbooks
- generate changelogs for all git located cookbooks

This plugin works in policyfile style repositories

## Todos

- (optionaly) link commit ref to their web page to ease reviews
- support more cookbook sources
