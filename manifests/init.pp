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
# [*handlers*]
# An array of handlers to use for this check. Set to [] if this check should
# spawn no handlers. Defaults to ['default'], which uses standard Yelp
# sensu_handlers that are 'team'-aware.
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
# [*remediation_action*]
# Which script should run when a check fails?
#
# [*remediation_retries*]
# How many times should the script run before the check is marked as failed?
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
# [*source*]
# String that identifies the source of this event or an entity (such as
# cluster, environment, datacenter, etc) to which it belongs.
# Should not be tied to a host that generated
# this event because it can come from any host where this check is deployed.
#
# [*tags*]
# An array of arbitrary tags that can be used in handlers for different metadata needs
# such as labels in JIRA handlers. This is optional and is empty by default
#
# [*subdue*]
# A hash the determines if and when a check should be silenced for a peroid of time,
# such as within working hours.
#
# This, by default allows you to set the $::override_sensu_checks_to fact
# in /etc/facter/facts.d to stop checks on a single machine from alerting via the
# normal mechanism. Setting this to false will stop this mechanism from applying
# to a check.
#
define monitoring_check (
  $command,
  $runbook,
  $handlers              = pick(
                             hiera("monitoring_check::handlers::${title}", undef),
                             hiera('monitoring_check::handlers', undef),
                             ['default']
                           ),
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
  $remediation_action    = undef,
  $remediation_retries   = 1,
  $low_flap_threshold    = undef,
  $high_flap_threshold   = undef,
  $source                = undef,
  $can_override          = true,
  $tags                  = [],
  $subdue                = undef,
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
  $ticket_real = str2bool($ticket)
  validate_array($tags)

  validate_array($handlers)
  validate_hash($sensu_custom)
  if $subdue != undef {
    validate_hash($subdue)
  }

  $interval_s = human_time_to_seconds($check_every)
  validate_re($interval_s, '^\d+$')

  if $timeout {
    $timeout_s = human_time_to_seconds($timeout)
  } else {
    $timeout_s = min($interval_s, 3600)
  }

  $alert_after_s = human_time_to_seconds($alert_after)

  validate_re("$alert_after_s", '^\d+$')
  validate_re("$realert_every", '^(-)?\d+$')

  if $source != undef {
    validate_re("$source", '^[\w\.-]+$', 'Source cannot contain whitespace or special characters')
  }

  # TODO: Handle this logic at the handler level?
  if $irc_channels != undef {
    $irc_channel_array = any2array($irc_channels)
  } else {
    $team_hash = $team_data
    $irc_channel_array = $team_hash[$team]['notifications_irc_channel']
  }

  if $remediation_action != undef {
    include monitoring_check::remediation

    validate_re($remediation_action, '^/.*', "Your command, ${remediation_action}, must use a full path")
    validate_integer($remediation_retries)

    $safe_command = shell_escape($command)
    $safe_remediation_action = shell_escape($remediation_action)

    $sudo_command = "${monitoring_check::params::etc_dir}/plugins/remediation.sh -n \"${name}\" -c ${safe_command} -a ${safe_remediation_action} -r ${remediation_retries}"
  } else {
    $sudo_command = $command
  }

  if str2bool($needs_sudo) {
    validate_re($sudo_command, '^/.*', "Your command, ${sudo_command}, must use a full path if you are going to use sudo")
    $real_command = "sudo -H -u ${sudo_user} -- ${sudo_command}"
    $cmd = regsubst($sudo_command, '^(\S+).*','\1') # Strip the options off, leaving just the check script
    if str2bool($use_sensu) {
      sudo::conf { "sensu_${title}":
        priority => 10,
        content  => "sensu       ALL=(${sudo_user}) NOPASSWD: ${cmd}\nDefaults!${cmd} !requiretty",
      } ->
      Sensu::Check[$name]
    }
  }
  else {
    $real_command = $sudo_command
  }

  $base_dict = {
    alert_after        => $alert_after_s,
    realert_every      => $realert_every,
    runbook            => $runbook,
    sla                => $sla,
    team               => $team,
    irc_channels       => $irc_channel_array,
    notification_email => $notification_email,
    ticket             => $ticket_real,
    project            => $project,
    page               => str2bool($page),
    tip                => $tip,
    habitat            => $::habitat,
    tags               => $tags,
  }
  if getvar('::override_sensu_checks_to') and $can_override {
    $with_override = merge($base_dict, {
      'team'             => 'noop',
      notification_email => $::override_sensu_checks_to,
    })
  } else {
    $with_override = $base_dict
  }
  $custom = merge($with_override, $sensu_custom)

  if str2bool($use_sensu) {
    if !defined(Class['sensu']) {
      fail("monitoring_check $title defined before the sensu class was included")
    }
    $sensu_check_params = delete_undef_values({
      handlers            => $handlers,
      command             => $real_command,
      interval            => $interval_s,
      timeout             => $timeout_s,
      low_flap_threshold  => $low_flap_threshold,
      high_flap_threshold => $high_flap_threshold,
      dependencies        => any2array($dependencies),
      custom              => $custom,
      source              => $source,
      subdue              => $subdue,
    })
    # quotes around $name are needed to ensure its value comes from monitoring_check
    create_resources('sensu::check', { "${name}" => $sensu_check_params })
  }
}
