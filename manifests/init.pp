# == Define: monitoring_check
#
# A define for managing monitoring checks - wraps sensu::check giving
# less bolierplate and yelp specific runbook functionality.
#
# === Parameters
#
# [*command*]
# The check command to run. This should be a standard nagios/sensu type check.
#
# [*runbook*]
# The URI to the google doc runbook for this check
# Should be of the form: y/my_runbook_name (preferred), or
# http://...some.uri. This is required.
#
# [*needs_sudo*]
# Boolean for if to run this check with sudo. Defaults to false
#
# [*sudo_user*]
# The user to sudo to (if needs_sudo is true). Defaults to root
#
# [*check_every*]
# How often to run this check. Can be an integer number of seconds, or an
# abbreviation such as '2m' for 120 seconds, or '2h' for 7200 seconds.
# Defaults to 1m.
#
# [*timeout*]
# How long the check will be allowed to run before it is killed and reported
# as failed. Defaults to the check_every frequency.
#
# [*alert_after*]
# How long a check is allowed to be failing for before alerting (pagerduty/irc).
# Can be an integer number of seconds, or an abbreviattion
# Defaults to 0s, meaning sensu will alert as soon as the check fails.
#
# [*realert_every*]
# Number of event occurrences before the handler should take action.
# For example, 10, would mean only re-notify every 10 fails.
# This logic only occurs after the alert_after time has expired.
# Defaults to -1 which means sensu will use exponential backoff.
#
# [*team*]
# The team responsible for this check (i.e. which team's pagerduty to escalate to)
# Defaults to operations, allowed to be any team in the hiera _sensu::teams_ key.
#
# [*page*]
# Boolean. If this alert should be escalated through to pagerduty.
# Every page also goes to a mandatory ${team}-pages, and is not configurable.
# Defaults to false.
#
# [*irc_channels*]
# Array of IRC channels to send notfications to. Set this to multiple channels
# if other teams are interested in your notifications. Set to [] if you need
# no IRC notifcations. (like, motd only or page only)
# Defaults to nil, which uses ${team}-notifications default from the irc handler.
#
# [*notification_email*]
# A string for the mailto for emails for alerts. (paging and non-paging)
# Defaults to undef, which makes the handler use the global team default.
# Use false if you want the alert to never send emails.
# It *can* take a comma separated list as an argument like a normal email mailto.
#
# [*ticket*]
# Boolean. Determines if the JIRA handler is executed or not. Defaults to false.
#
# [*project*]
# Optionally set the JIRA project for a check. Otherwise if, if ticket=>true,
# then it will use the project set for the team.
#
# [*tip*]
# A quick tip for how to respond to / clear the alert without having to read the
# runbook. Optional (and custom checks are recommended to put the tip into the
# check output).
#
# [*sla*]
# Allows you to define the SLA for the service you are monitoring. Notice
# it is lower case!
#
# This is (currently) just a human readable string usable in handlers to give
# more context about the urgency of an alert when you see it in a
# ticket/page/email/irc.
#
# [*dependencies*]
# A list of dependencies for this check to be escalated if it's critical.
# If any of these dependencies are critical then the check will not be escalated
# by the handler.
#
# Dependencies are simply other check names, or certname/checkname for
# checks on other hosts.
# Defaults to empty
#
# [*use_sensu*]
# Implement the monitoring check with sensu. Defaults to true, and
# it's silly to set it to false until another monitoring system is supported.
#
# [*sensu_custom*]
# A hash of custom parameters to inject into the sensu check JSON output.
# These will override any parameters configured by the wrapper.
# Defaults to an empty hash.
#
# [*low_flap_threshold*]
# Custom threshold at which to consider this service as having stopped flapping.
# Defaults to unset
# See http://nagios.sourceforge.net/docs/3_0/flapping.html for more details
#
# [*high_flap_threshold*]
# Custom threshold to consider this service flapping at
# Defaults to unset
#
# [*can_override*]
# A boolean that defaults to true for if the $::override_sensu_checks_to
# fact can be used to override the team (to 'noop') and the notification_email
# parameter (to the value of $::override_sensu_checks_to).
# Defaults to true.
#
# This, by default allows you to set the $::override_sensu_checks_to fact
# in /etc/facter/facts.d to stop checks on a single machine from alerting via the
# normal mechanism. Setting this to false will stop this mechanism from applying
# to a check.
#
# [*annotation*]
# The line of code that should be referenced as the "originator" for this
# monitoring check. Obviously there is an entire call stack to choose from.
# Try to use the most relevant/helpful value here.
#
define monitoring_check (
  $command,
  $runbook,
  $needs_sudo            = false,
  $sudo_user             = 'root',
  $check_every           = '1m',
  $timeout               = undef,
  $alert_after           = '0s',
  $realert_every         = '-1',
  $team                  = 'operations',
  $page                  = false,
  $irc_channels          = undef,
  $notification_email    = 'undef',
  $ticket                = false,
  $project               = false,
  $tip                   = false,
  $sla                   = 'No SLA defined.',
  $dependencies          = [],
  $use_sensu             = hiera('sensu_enabled', true),
  $sensu_custom          = {},
  $low_flap_threshold    = undef,
  $high_flap_threshold   = undef,
  $can_override          = true,
  $annotation            = annotation_guess(),
) {

  include monitoring_check::params
  $team_data = $monitoring_check::params::team_data

  # Catch RE errors before they stop sensu:
  # https://github.com/sensu/sensu/blob/master/lib/sensu/settings.rb#L215
  validate_re($name, '^[\w\.-]+$', "Your sensu check name has special chars sensu won't like: ${name}" )

  validate_string($command)
  validate_string($runbook)
  validate_re($runbook, '^(https?://|y/)')
  validate_string($team)
  if size(keys($team_data)) == 0 {
    fail("No sensu_handlers::teams data could be loaded - need at least 1 team")
  }
  $team_names = join(keys($team_data), '|')
  validate_re($team, "^(${team_names})$")
  validate_bool($ticket)

  validate_hash($sensu_custom)

  $interval_s = human_time_to_seconds($check_every)
  validate_re($interval_s, '^\d+$')

  if $timeout {
    $timeout_s = human_time_to_seconds($timeout)
  } else {
    $timeout_s = min($interval_s, 3600)
  }

  $alert_after_s = human_time_to_seconds($alert_after)
  validate_re($alert_after_s, '^\d+$')
  validate_re($realert_every, '^(-)?\d+$')

  # TODO: Handle this logic at the handler level?
  if $irc_channels != undef {
    $irc_channel_array = any2array($irc_channels)
  } else {
    $team_hash = $team_data
    $irc_channel_array = $team_hash[$team]['notifications_irc_channel']
  }

  if str2bool($needs_sudo) {
    validate_re($command, '^/.*', "Your command, ${command}, must use a full path if you are going to use sudo")
    $real_command = "sudo_isnt_ready || sudo -n -H -u ${sudo_user} -- ${command}"
    $cmd = regsubst($command, '^(\S+).*','\1') # Strip the options off, leaving just the check script
    if str2bool($use_sensu) {
      sudo::conf { "sensu_${title}":
        priority => 10,
        content  => "sensu       ALL=(${sudo_user}) NOPASSWD: ${cmd}\nDefaults!${cmd} !requiretty",
      } ->
      Sensu::Check[$name]
    }
  }
  else {
    $real_command = $command
  }

  if getvar('::override_sensu_checks_to') and $can_override {
    $override_custom = {
      'team'             => 'noop',
      notification_email => $::override_sensu_checks_to,
    }
  }
  else {
    $override_custom = {}
  }

  if str2bool($use_sensu) {
    sensu::check { $name:
      handlers            => 'default', # Always use the default handler, it'll route things via escalation_team
      command             => $real_command,
      interval            => $interval_s,
      timeout             => $timeout_s,
      low_flap_threshold  => $high_flap_threshold,
      high_flap_threshold => $low_flap_threshold,
      dependencies        => any2array($dependencies),
      custom              => merge(merge({
        alert_after           => $alert_after_s,
        realert_every         => $realert_every,
        runbook               => $runbook,
        annotation            => $annotation,
        sla                   => $sla,
        team                  => $team,
        irc_channels          => $irc_channel_array,
        notification_email    => $notification_email,
        ticket                => $ticket,
        project               => $project,
        page                  => str2bool($page),
        tip                   => $tip,
      }, $override_custom), $sensu_custom)
    }
  }
}
