# == Class monitoring_check::params
#
# The params class of monitoring_check allows you to set the defaults for your
# environment once, which are then inherited by all the other monitoring_check
# defines
#
# == Parameters
#
# [*expose_team_data*]
#  Bool to have a json deposited in /etc/sensu/teams.json for other tools
#  to use.
#
# [*team_data*]
#  Hash of team data from sensu_handlers so we can validate incoming teams.
#
# [*bin_path*]
#  String to represent where to stick binaries that puppet deploys. Defaults
#  to '/usr/bin'
#
class monitoring_check::params (
  $expose_team_data = hiera('sensu_enabled', true),
  # Pull the team data configuration from the sensu_handlers module in order
  # to validate the given inputs.
  $team_data = hiera('sensu_handlers::teams', {}),
  $bin_path = '/usr/bin',
) {

  # Expose the team metadata as json for other tools to validate against
  validate_bool($expose_team_data)
  validate_hash($team_data)
  if $expose_team_data {
    $team_data_hash = {
      'team_data' => $team_data
    }
    file { '/etc/sensu/team_data.json':
      owner   => 'sensu',
      group   => 'sensu',
      mode    => '0444',
      content => inline_template('<%= require "json"; JSON.generate @team_data_hash %>'),
    }
  }

  if getvar('::override_sensu_checks_to') {
    # This fact can be dropped in by outside tools.
    # If it exists, lets ensure the file so it sticks around and is not purged.
    file { '/etc/facter/facts.d/override_sensu_checks_to.txt':
      ensure => 'file',
      owner  => 'root',
      group  => 'root',
      mode   => '0644',
    }
  }

  file { "${bin_path}/send-test-sensu-alert":
    ensure => 'file',
    mode   => '0555',
    owner  => 'root',
    group  => 'root',
    source => 'puppet:///modules/monitoring_check/send-test-sensu-alert',
  }

  file { "${bin_path}/sudo_isnt_ready":
    ensure => 'file',
    mode   => '0555',
    owner  => 'root',
    group  => 'root',
    source => 'puppet:///modules/monitoring_check/sudo_isnt_ready',
  }

}
